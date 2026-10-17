-- Suppression de compte depuis l'application (exigence App Store 5.1.1(v)).
--
-- 1. request_account_deletion : l'utilisateur confirme (mot « SUPPRIMER » + code du responsable
--    si sa boutique en a un). Ses boutiques sont fermées aux commandes en ligne tout de suite ;
--    l'application n'affiche plus que l'écran « suppression programmée ».
-- 2. Pendant 30 jours, cancel_account_deletion remet tout comme avant.
-- 3. Ensuite la fonction Edge « account-purge » (lancée chaque nuit) efface les photos du stockage
--    puis le compte : la suppression du compte efface en cascade ses boutiques et tout leur contenu
--    (ventes, stock, arrivages, charges, commandes, caissiers, journal).

create table if not exists public.account_deletion_requests (
  user_id uuid primary key references auth.users(id) on delete cascade,
  requested_at timestamptz not null default now(),
  purge_after timestamptz not null default now() + interval '30 days',
  -- Canaux de commande en ligne coupés par la demande, rallumés si elle est annulée.
  disabled_channels uuid[] not null default '{}'
);
alter table public.account_deletion_requests enable row level security;
revoke all on public.account_deletion_requests from anon, authenticated;

/** État de la demande de l'utilisateur connecté : {pending, requested_at, purge_after}. */
create or replace function public.my_account_deletion()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_row public.account_deletion_requests%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into v_row from public.account_deletion_requests where user_id = auth.uid();
  if not found then return pg_catalog.jsonb_build_object('pending', false); end if;
  return pg_catalog.jsonb_build_object('pending', true, 'requested_at', v_row.requested_at,
                                       'purge_after', v_row.purge_after);
end;
$$;

/**
 * Programme la suppression du compte dans 30 jours. Renvoie {status: ok|invalid|locked|confirm}
 * sans lever d'erreur pour un mauvais code (le compteur d'essais du code doit être enregistré).
 */
create or replace function public.request_account_deletion(p_confirm text, p_owner_pin text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_shop record;
  v_check jsonb;
  v_disabled uuid[] := '{}';
  v_row public.account_deletion_requests%rowtype;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if pg_catalog.upper(pg_catalog.btrim(coalesce(p_confirm, ''))) <> 'SUPPRIMER' then
    return pg_catalog.jsonb_build_object('status', 'confirm');
  end if;
  select * into v_row from public.account_deletion_requests where user_id = v_uid;
  if found then
    return pg_catalog.jsonb_build_object('status', 'ok', 'purge_after', v_row.purge_after);
  end if;
  -- Le code du responsable protège chaque boutique qui en a un (compte de gestion partagé).
  for v_shop in select s.id from public.shops s where s.owner_id = v_uid loop
    v_check := public.owner_pin_check(v_shop.id, p_owner_pin);
    if v_check ->> 'status' in ('invalid', 'locked') then
      perform public.owner_pin_audit_failure(v_shop.id, 'account_deletion', v_check);
      return v_check;
    end if;
  end loop;

  select coalesce(pg_catalog.array_agg(c.shop_id), '{}') into v_disabled
  from public.public_order_channels c
  join public.shops s on s.id = c.shop_id
  where s.owner_id = v_uid and c.enabled;
  update public.public_order_channels set enabled = false where shop_id = any(v_disabled);

  insert into public.account_deletion_requests(user_id, disabled_channels)
  values (v_uid, v_disabled)
  returning * into v_row;
  for v_shop in select s.id from public.shops s where s.owner_id = v_uid loop
    perform public.shop_audit(v_shop.id, 'account_deletion_requested', v_uid::text,
      pg_catalog.jsonb_build_object('purge_after', v_row.purge_after));
  end loop;
  return pg_catalog.jsonb_build_object('status', 'ok', 'purge_after', v_row.purge_after);
end;
$$;

/** Annule la demande : le compte et les boutiques reviennent comme avant. */
create or replace function public.cancel_account_deletion()
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.account_deletion_requests%rowtype;
  v_shop record;
begin
  if v_uid is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  delete from public.account_deletion_requests where user_id = v_uid returning * into v_row;
  if not found then return pg_catalog.jsonb_build_object('pending', false); end if;
  update public.public_order_channels c set enabled = true
  from public.shops s
  where c.shop_id = any(v_row.disabled_channels) and s.id = c.shop_id and s.owner_id = v_uid;
  for v_shop in select s.id from public.shops s where s.owner_id = v_uid loop
    perform public.shop_audit(v_shop.id, 'account_deletion_cancelled', v_uid::text, '{}'::jsonb);
  end loop;
  return pg_catalog.jsonb_build_object('pending', false);
end;
$$;

-- Jeton de la purge nocturne : gardé dans Vault, jamais affiché ; la fonction Edge le compare.
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'covi_account_purge_token') then
    perform vault.create_secret(pg_catalog.encode(extensions.gen_random_bytes(32), 'hex'),
                                'covi_account_purge_token',
                                'Autorise la purge nocturne des comptes supprimés');
  end if;
end $$;

/**
 * Comptes dont le délai de 30 jours est passé, avec leurs boutiques (pour effacer les photos).
 * Réservé à la fonction Edge (service_role) et à son jeton : renvoie [] si le jeton est faux.
 */
create or replace function public.account_purge_due(p_token text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets
  where name = 'covi_account_purge_token';
  if v_secret is null or p_token is null or p_token <> v_secret then
    raise exception 'Invalid purge token' using errcode = '42501';
  end if;
  return coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'user_id', r.user_id,
      'shop_ids', coalesce((select pg_catalog.jsonb_agg(s.id) from public.shops s
                            where s.owner_id = r.user_id), '[]'::jsonb)))
    from public.account_deletion_requests r
    where r.purge_after <= now()
  ), '[]'::jsonb);
end;
$$;

/**
 * Purge, étape 1 : efface les boutiques du compte (et en cascade tout leur contenu). Le compte
 * lui-même est ensuite supprimé par la fonction Edge (API d'administration) : les boutiques
 * doivent partir avant, car certaines lignes (caissiers, caisses) gardent l'auteur.
 */
create or replace function public.account_purge_shops(p_token text, p_user_id uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_secret text;
  v_count integer;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets
  where name = 'covi_account_purge_token';
  if v_secret is null or p_token is null or p_token <> v_secret then
    raise exception 'Invalid purge token' using errcode = '42501';
  end if;
  if not exists (select 1 from public.account_deletion_requests
                 where user_id = p_user_id and purge_after <= now()) then
    raise exception 'Account not due for purge';
  end if;
  -- Dans l'ordre : ce qui pointe vers les produits, les ventes ou les caissiers part d'abord.
  delete from public.public_orders o using public.shops s
  where o.shop_id = s.id and s.owner_id = p_user_id;
  delete from public.sales v using public.shops s
  where v.shop_id = s.id and s.owner_id = p_user_id;
  delete from public.shops where owner_id = p_user_id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.my_account_deletion() from public, anon;
revoke all on function public.request_account_deletion(text, text) from public, anon;
revoke all on function public.cancel_account_deletion() from public, anon;
revoke all on function public.account_purge_due(text) from public, anon, authenticated;
grant execute on function public.my_account_deletion() to authenticated;
grant execute on function public.request_account_deletion(text, text) to authenticated;
grant execute on function public.cancel_account_deletion() to authenticated;
grant execute on function public.account_purge_due(text) to service_role;
revoke all on function public.account_purge_shops(text, uuid) from public, anon, authenticated;
grant execute on function public.account_purge_shops(text, uuid) to service_role;
