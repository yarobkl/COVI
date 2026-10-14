-- Sécurité P0 : une caissière authentifiée ne doit pas contourner le pavé PIN en appelant
-- directement record_sale / record_cart_sale avec la clé publique Supabase.
-- Requiert les migrations 20261014090000, 20261014090050 et 20261014090100.
-- Aucun changement des ventes réelles. Les déverrouillages expirent après 5 minutes
-- d'inactivité de vente et sont liés à la session d'authentification Supabase.
-- Supabase Auth produit un claim JWT signé session_id (UUID). Sans ce claim, fail closed.

create table if not exists public.member_pin_unlocks (
  member_id uuid not null references public.shop_members(id) on delete cascade,
  session_id uuid not null,
  unlocked_until timestamptz not null,
  primary key (member_id, session_id)
);
create index if not exists member_pin_unlocks_expiry_idx
  on public.member_pin_unlocks(unlocked_until);
alter table public.member_pin_unlocks enable row level security;
revoke all on public.member_pin_unlocks from public, anon, authenticated;

-- Seul un JWT valide transmis par PostgREST peut remplir request.jwt.claims en production.
-- Le second GUC, utilisé dans les tests SQL locaux, reproduit l'ancien format PostgREST.
create or replace function public.cashier_session_id()
returns uuid
language sql
stable
set search_path to ''
as $function$
  select pg_catalog.coalesce(
    pg_catalog.nullif(
      pg_catalog.nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb
        ->> 'session_id', ''),
    pg_catalog.nullif(pg_catalog.current_setting('request.jwt.claim.session_id', true), '')
  )::uuid
$function$;

-- Écrit une preuve uniquement pour le compte actif qui possède le PIN, jamais pour autrui.
create or replace function public.cashier_touch_unlock(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_session uuid := public.cashier_session_id();
begin
  if v_session is null then
    raise exception 'PIN unlock required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.shop_members m
    join public.member_pins p on p.member_id = m.id
    where m.id = p_member_id and m.user_id = auth.uid() and m.active
      and p.pin_hash is not null and not p.must_change
      and (p.locked_until is null or p.locked_until <= pg_catalog.now())
  ) then
    raise exception 'PIN unlock required' using errcode = '42501';
  end if;
  insert into public.member_pin_unlocks(member_id, session_id, unlocked_until)
  values(p_member_id, v_session, pg_catalog.now() + interval '5 minutes')
  on conflict (member_id, session_id)
    do update set unlocked_until = excluded.unlocked_until;
end;
$function$;

-- Les fonctions de vente interrogent cette preuve côté serveur ; pas de simple booléen front.
create or replace function public.cashier_pin_unlocked(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select exists (
    select 1 from public.member_pin_unlocks u
    join public.shop_members m on m.id = u.member_id
    join public.member_pins p on p.member_id = u.member_id
    where u.member_id = p_member_id
      and u.session_id = public.cashier_session_id()
      and u.unlocked_until > pg_catalog.now()
      and m.user_id = auth.uid() and m.active
      and p.pin_hash is not null and not p.must_change
      and (p.locked_until is null or p.locked_until <= pg_catalog.now())
  )
$function$;

-- Nouvelle définition : un PIN juste accorde une preuve éphémère pour la session JWT.
-- Après un mauvais code, cette session ne conserve plus d'autorisation de vente.
create or replace function public.verify_my_pin(p_shop_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_member public.shop_members%rowtype;
  v_result jsonb;
begin
  v_member := public.assert_active_member(p_shop_id);
  v_result := public.member_pin_check(v_member.id, p_pin);
  if v_result ->> 'status' = 'ok' then
    perform public.cashier_touch_unlock(v_member.id);
  else
    delete from public.member_pin_unlocks
    where member_id = v_member.id and session_id = public.cashier_session_id();
  end if;
  return v_result;
end;
$function$;

-- Le premier choix (ou le remplacement) d'un PIN déverrouille la session en cours,
-- et révoque les autres sessions déjà déverrouillées pour ce caissier.
-- La réinitialisation par le responsable (pin_hash => NULL) invalide tous les déverrouillages.
create or replace function public.cashier_pin_changed()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  delete from public.member_pin_unlocks where member_id = new.member_id;
  if new.pin_hash is not null and exists (
    select 1 from public.shop_members m
    where m.id = new.member_id and m.user_id = auth.uid() and m.active
  ) then
    perform public.cashier_touch_unlock(new.member_id);
  end if;
  return new;
end;
$function$;
drop trigger if exists cashier_pin_changed on public.member_pins;
create trigger cashier_pin_changed
after update of pin_hash on public.member_pins
for each row
when (old.pin_hash is distinct from new.pin_hash)
execute function public.cashier_pin_changed();

-- La désactivation d'un caissier coupe immédiatement toutes ses sessions PIN.
create or replace function public.cashier_deactivated()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  delete from public.member_pin_unlocks where member_id = new.id;
  return new;
end;
$function$;
drop trigger if exists cashier_deactivated on public.shop_members;
create trigger cashier_deactivated
after update of active on public.shop_members
for each row
when (old.active is distinct from new.active)
execute function public.cashier_deactivated();

-- Le propriétaire demeure autorisé. Le vendeur caissier, lui, doit avoir déverrouillé
-- son PIN dans cette session JWT, et la preuve est prolongée après chaque vente.
create or replace function public.sale_seller(
  p_shop_id uuid,
  p_till_session text,
  out seller_id uuid,
  out max_discount_pct numeric
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_is_owner boolean;
  v_member public.shop_members%rowtype;
begin
  v_is_owner := exists (
    select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_uid);
  if p_till_session is not null then
    if not v_is_owner then
      raise exception 'Till session invalid' using errcode = '42501';
    end if;
    v_member := public.till_session_member(p_shop_id, p_till_session);
    seller_id := v_member.user_id;
    max_discount_pct := v_member.max_discount_pct;
    return;
  end if;
  if v_is_owner then
    seller_id := v_uid;
    max_discount_pct := null;
    return;
  end if;
  v_member := public.assert_active_member(p_shop_id);
  if not exists (select 1 from public.member_pins p
                 where p.member_id = v_member.id and p.pin_hash is not null) then
    raise exception 'PIN required' using errcode = '42501';
  end if;
  if not public.cashier_pin_unlocked(v_member.id) then
    raise exception 'PIN unlock required' using errcode = '42501';
  end if;
  -- Sliding expiry: active cashiers may keep selling without entering the PIN every five minutes.
  perform public.cashier_touch_unlock(v_member.id);
  seller_id := v_uid;
  max_discount_pct := v_member.max_discount_pct;
end;
$function$;

-- Même contrat que l'ancienne fonction publique de lecture des permissions,
-- désormais cohérent avec la vérification réellement exigée par record_sale.
create or replace function public.has_shop_permission(p_shop_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select pg_catalog.coalesce(
    (exists (select 1 from public.shops s where s.id = p_shop_id and s.owner_id = auth.uid())
      and p_permission in ('manage', 'sell', 'view_products', 'view_own_sales', 'view_shop_sales'))
    or exists (
      select 1 from public.shop_members m
      where m.shop_id = p_shop_id and m.user_id = auth.uid() and m.active
        and (p_permission in ('view_products', 'view_own_sales')
             or (p_permission = 'view_shop_sales' and m.can_view_shop_sales)
             or (p_permission = 'sell' and public.cashier_pin_unlocked(m.id))))
  , false)
$function$;

-- Ne jamais exposer les fonctions auxiliaires SECURITY DEFINER aux comptes API.
revoke execute on function public.cashier_session_id() from public, anon, authenticated;
revoke execute on function public.cashier_touch_unlock(uuid) from public, anon, authenticated;
revoke execute on function public.cashier_pin_unlocked(uuid) from public, anon, authenticated;
revoke execute on function public.cashier_pin_changed() from public, anon, authenticated;
revoke execute on function public.cashier_deactivated() from public, anon, authenticated;
-- Les entrées API déjà existantes restent utilisables par un compte authentifié uniquement.
revoke execute on function public.verify_my_pin(uuid, text) from public, anon;
revoke execute on function public.has_shop_permission(uuid, text) from public, anon;
grant execute on function public.verify_my_pin(uuid, text) to authenticated;
grant execute on function public.has_shop_permission(uuid, text) to authenticated;
