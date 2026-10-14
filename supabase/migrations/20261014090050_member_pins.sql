-- Caisse multi-caissiers (2/3) : code PIN personnel des caissiers et sessions de caisse.
--
-- Décisions du propriétaire :
--   - chaque caissier a SON code PIN (4 à 6 chiffres), connu de lui seul. Le propriétaire ne le
--     voit jamais et ne peut que le réinitialiser (le caissier en choisit alors un nouveau) ;
--   - deux usages, tous deux vérifiés par la base :
--       (a) appareil personnel : le caissier est connecté à SON compte ; l'application verrouille
--           la caisse derrière son PIN (ouverture, inactivité) via verify_my_pin. Un membre sans
--           PIN défini ne peut pas vendre (has_shop_permission 'sell', record_sale/_cart_sale) ;
--       (b) appareil partagé connecté au compte du PROPRIÉTAIRE : « Changer de caissier » →
--           open_till_session(shop, membre, PIN) renvoie un jeton aléatoire (stocké haché,
--           valable 12 h ou jusqu'à close_till_session, lié à la boutique et au membre). Les
--           ventes passées avec ce jeton (p_till_session de record_sale / record_cart_sale) sont
--           attribuées à ce membre et limitées par SA remise maximale.
--
-- Stockage du PIN : bcrypt (pgcrypto crypt + gen_salt('bf', 10)), jamais en clair, jamais
-- renvoyé, jamais écrit dans le journal. 5 échecs (verify_my_pin, open_till_session ou ancien PIN
-- de set_my_pin, compteur commun par membre) → verrouillage 15 minutes.
--
-- Les échecs de PIN ne lèvent PAS d'exception (elle annulerait l'incrément du compteur) : les
-- fonctions renvoient un statut jsonb ('ok', 'invalid', 'locked', 'not_set').
--
-- pgcrypto : sur Supabase, l'extension vit dans le schéma `extensions` (fonctions qualifiées
-- extensions.crypt / extensions.gen_salt / extensions.gen_random_bytes). Le bloc ci-dessous
-- l'installe là si elle est absente et refuse de continuer si elle est ailleurs : mieux vaut un
-- échec de migration (atomique) qu'une fonction qui échoue à l'exécution.
--
-- Migration non destructive : uniquement des créations.

-- 0. pgcrypto dans le schéma extensions -------------------------------------------------------
do $$
declare
  v_schema text;
begin
  select n.nspname into v_schema
  from pg_catalog.pg_extension e join pg_catalog.pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pgcrypto';
  if v_schema is null then
    create schema if not exists extensions;
    create extension pgcrypto with schema extensions;
  elsif v_schema <> 'extensions' then
    raise exception 'pgcrypto must be installed in schema extensions (found in %)', v_schema;
  end if;
end
$$;

-- 1. Tables -------------------------------------------------------------------------------------

-- Une ligne par membre qui a (ou a eu) un PIN. pin_hash NULL = pas de PIN (jamais défini, ou
-- réinitialisé par le propriétaire : must_change = true).
create table if not exists public.member_pins (
  member_id uuid primary key references public.shop_members(id) on delete cascade,
  pin_hash text check (pin_hash is null or pin_hash like '$2_$%'),
  failed_attempts integer not null default 0 check (failed_attempts >= 0),
  locked_until timestamptz,
  must_change boolean not null default false,
  updated_at timestamptz not null default now()
);

-- Sessions de caisse d'un appareil partagé (cas b). Le jeton n'est stocké que haché (SHA-256).
create table if not exists public.till_sessions (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  member_id uuid not null references public.shop_members(id) on delete cascade,
  token_hash bytea not null unique,
  opened_by uuid references auth.users(id) on delete set null,
  opened_at timestamptz not null default now(),
  expires_at timestamptz not null,
  closed_at timestamptz,
  constraint till_sessions_expiry_check check (expires_at > opened_at)
);
create index if not exists till_sessions_member_idx on public.till_sessions (member_id)
  where closed_at is null;
create index if not exists till_sessions_shop_idx on public.till_sessions (shop_id);

drop trigger if exists member_pins_touch_updated_at on public.member_pins;
create trigger member_pins_touch_updated_at
  before update on public.member_pins
  for each row execute function public.touch_updated_at();

-- RLS active SANS politique : aucun accès direct, pas même du propriétaire. Tout passe par les
-- fonctions ci-dessous.
alter table public.member_pins enable row level security;
alter table public.till_sessions enable row level security;
revoke all on public.member_pins, public.till_sessions from public, anon, authenticated;

-- 2. Outils internes (non exécutables par les rôles d'API) ------------------------------------

-- Format et robustesse d'un nouveau PIN. Lève 'Invalid PIN format' ou 'PIN too simple'.
-- Refusés : tous chiffres identiques (0000, 111111), suites croissantes ou décroissantes
-- (1234, 456789, 4321, 987654), motifs répétés (1212, 121212, 123123, 112233 n'est pas un motif
-- répété mais figure dans la liste), et quelques codes très courants.
create or replace function public.member_pin_assert_strength(p_pin text)
returns void
language plpgsql
immutable
set search_path to ''
as $function$
declare
  v_len integer;
  v_up boolean := true;
  v_down boolean := true;
begin
  if p_pin is null or p_pin !~ '^[0-9]{4,6}$' then
    raise exception 'Invalid PIN format' using errcode = '22023';
  end if;
  v_len := char_length(p_pin);
  for i in 2 .. v_len loop
    if (pg_catalog.ascii(pg_catalog.substr(p_pin, i, 1)) - pg_catalog.ascii(pg_catalog.substr(p_pin, i - 1, 1))) <> 1 then
      v_up := false;
    end if;
    if (pg_catalog.ascii(pg_catalog.substr(p_pin, i, 1)) - pg_catalog.ascii(pg_catalog.substr(p_pin, i - 1, 1))) <> -1 then
      v_down := false;
    end if;
  end loop;
  if p_pin ~ '^(.)\1+$'                       -- 0000, 111111
     or v_up or v_down                         -- 1234, 4321, 012345, 987654
     or p_pin ~ '^(..)\1+$'                    -- 1212, 121212
     or p_pin ~ '^(...)\1$'                    -- 123123
     or p_pin in ('112233', '2580', '258000', '1122', '1004', '696969', '159753')
  then
    raise exception 'PIN too simple' using errcode = '22023';
  end if;
end;
$function$;

-- Vérifie le PIN d'un membre et met à jour le compteur d'échecs. Ne lève jamais d'exception
-- pour un mauvais PIN. Retour : {"status": "ok"} | {"status": "not_set"} |
-- {"status": "invalid", "attempts_left": n} | {"status": "locked", "retry_after": ts}.
-- À appeler uniquement depuis une fonction qui a déjà vérifié l'appelant.
create or replace function public.member_pin_check(p_member_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c_max_failures constant integer := 5;
  c_lock constant interval := interval '15 minutes';
  v_row public.member_pins%rowtype;
  v_failures integer;
begin
  select * into v_row from public.member_pins p where p.member_id = p_member_id for update;
  if not found or v_row.pin_hash is null then
    return pg_catalog.jsonb_build_object('status', 'not_set');
  end if;
  if v_row.locked_until is not null and v_row.locked_until > pg_catalog.now() then
    return pg_catalog.jsonb_build_object('status', 'locked', 'retry_after', v_row.locked_until);
  end if;
  if p_pin is not null and p_pin ~ '^[0-9]{4,6}$'
     and extensions.crypt(p_pin, v_row.pin_hash) = v_row.pin_hash then
    if v_row.failed_attempts <> 0 or v_row.locked_until is not null then
      update public.member_pins
      set failed_attempts = 0, locked_until = null
      where member_id = p_member_id;
    end if;
    return pg_catalog.jsonb_build_object('status', 'ok');
  end if;
  -- Échec. Après la fin d'un verrouillage, le compteur repart de zéro.
  v_failures := case when v_row.locked_until is not null then 0 else v_row.failed_attempts end + 1;
  if v_failures >= c_max_failures then
    update public.member_pins
    set failed_attempts = v_failures, locked_until = pg_catalog.now() + c_lock
    where member_id = p_member_id;
    return pg_catalog.jsonb_build_object('status', 'locked',
      'retry_after', pg_catalog.now() + c_lock);
  end if;
  update public.member_pins
  set failed_attempts = v_failures, locked_until = null
  where member_id = p_member_id;
  return pg_catalog.jsonb_build_object('status', 'invalid',
    'attempts_left', c_max_failures - v_failures);
end;
$function$;

-- Membre ACTIF de la boutique correspondant à l'appelant. Lève 'Shop not found' (42501) sinon.
create or replace function public.assert_active_member(p_shop_id uuid)
returns public.shop_members
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_member public.shop_members%rowtype;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into v_member from public.shop_members m
  where m.shop_id = p_shop_id and m.user_id = v_uid and m.active;
  if not found then
    raise exception 'Shop not found' using errcode = '42501';
  end if;
  return v_member;
end;
$function$;

-- Membre ACTIF lié à un jeton de session de caisse valide pour cette boutique. Lève
-- 'Till session invalid' (42501) si le jeton est inconnu, d'une autre boutique, fermé, expiré,
-- ou si le membre a été désactivé ou n'a plus de PIN. Ne vérifie PAS l'appelant.
create or replace function public.till_session_member(p_shop_id uuid, p_token text)
returns public.shop_members
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_member public.shop_members%rowtype;
begin
  select m.* into v_member
  from public.till_sessions t
  join public.shop_members m on m.id = t.member_id
  join public.member_pins p on p.member_id = m.id
  where p_token is not null and p_token ~ '^[0-9a-f]{64}$'
    and t.token_hash = pg_catalog.sha256(pg_catalog.convert_to('covi-till:' || p_token, 'UTF8'))
    and t.shop_id = p_shop_id and m.shop_id = p_shop_id
    and t.closed_at is null and t.expires_at > pg_catalog.now()
    and m.active and p.pin_hash is not null;
  if not found then
    raise exception 'Till session invalid' using errcode = '42501';
  end if;
  return v_member;
end;
$function$;

-- 3. Autorisations ------------------------------------------------------------------------------

-- Permissions : 'manage' (propriétaire seul) ; 'view_products' et 'view_own_sales' (propriétaire
-- ou membre actif) ; 'sell' (propriétaire, ou membre actif AYANT un PIN) ; 'view_shop_sales'
-- (propriétaire, ou membre actif avec can_view_shop_sales). Permission inconnue : false.
-- Ne renseigne que sur l'appelant (auth.uid()).
create or replace function public.has_shop_permission(p_shop_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    (exists (select 1 from public.shops s where s.id = p_shop_id and s.owner_id = auth.uid())
      and p_permission in ('manage', 'sell', 'view_products', 'view_own_sales', 'view_shop_sales'))
    or exists (
      select 1 from public.shop_members m
      where m.shop_id = p_shop_id and m.user_id = auth.uid() and m.active
        and (p_permission in ('view_products', 'view_own_sales')
             or (p_permission = 'view_shop_sales' and m.can_view_shop_sales)
             or (p_permission = 'sell' and exists (
                   select 1 from public.member_pins p
                   where p.member_id = m.id and p.pin_hash is not null)))
    ),
    false)
$function$;

-- 4. RPC du caissier (son propre compte) ------------------------------------------------------

-- Définit ou change SON PIN pour une boutique.
--   - premier PIN, ou après réinitialisation par le propriétaire : p_current_pin ignoré ;
--   - changement : p_current_pin obligatoire et vérifié (compte comme un essai).
-- Retour : {"status": "ok"} | {"status": "invalid", "attempts_left"} | {"status": "locked",
-- "retry_after"}. Exceptions : 'Authentication required', 'Shop not found' (42501),
-- 'Invalid PIN format', 'PIN too simple' (22023).
create or replace function public.set_my_pin(
  p_shop_id uuid,
  p_new_pin text,
  p_current_pin text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_member public.shop_members%rowtype;
  v_check jsonb;
  v_had_pin boolean;
begin
  v_member := public.assert_active_member(p_shop_id);
  perform public.member_pin_assert_strength(p_new_pin);
  -- Ligne créée au besoin puis verrouillée (sérialise les changements concurrents).
  insert into public.member_pins (member_id) values (v_member.id) on conflict do nothing;
  select p.pin_hash is not null into v_had_pin
  from public.member_pins p where p.member_id = v_member.id for update;
  if v_had_pin then
    v_check := public.member_pin_check(v_member.id, p_current_pin);
    if v_check ->> 'status' <> 'ok' then
      return v_check;
    end if;
  end if;
  update public.member_pins
  set pin_hash = extensions.crypt(p_new_pin, extensions.gen_salt('bf', 10)),
      failed_attempts = 0, locked_until = null, must_change = false
  where member_id = v_member.id;
  perform public.shop_audit(p_shop_id, case when v_had_pin then 'pin_changed' else 'pin_set' end,
    v_member.id::text, pg_catalog.jsonb_build_object('display_name', v_member.display_name));
  return pg_catalog.jsonb_build_object('status', 'ok');
end;
$function$;

-- Vérifie SON PIN (déverrouillage de la caisse sur un appareil personnel).
-- Retour : voir member_pin_check ('ok', 'invalid', 'locked', 'not_set').
create or replace function public.verify_my_pin(p_shop_id uuid, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_member public.shop_members%rowtype;
begin
  v_member := public.assert_active_member(p_shop_id);
  return public.member_pin_check(v_member.id, p_pin);
end;
$function$;

-- Boutiques où l'appelant est membre ACTIF, avec ses propres permissions et l'état de son PIN.
-- Seules des colonnes sûres de shops sont exposées (pas owner_id, pas de coordonnées GPS).
create or replace function public.my_member_shops()
returns table (
  member_id uuid, shop_id uuid, shop_name text, shop_city text, shop_country text,
  shop_currency text, display_name text, role text, can_view_shop_sales boolean,
  max_discount_pct numeric, pin_set boolean, pin_must_change boolean
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  return query
    select m.id, s.id, s.name, s.city, s.country, s.currency, m.display_name, m.role,
           m.can_view_shop_sales, m.max_discount_pct,
           coalesce(p.pin_hash is not null, false), coalesce(p.must_change, false)
    from public.shop_members m
    join public.shops s on s.id = m.shop_id
    left join public.member_pins p on p.member_id = m.id
    where m.user_id = auth.uid() and m.active
    order by s.name;
end;
$function$;

-- 5. RPC du propriétaire ------------------------------------------------------------------------

-- Équipe de la boutique, avec l'état du PIN (jamais le PIN ni son empreinte).
create or replace function public.list_shop_members(p_shop_id uuid)
returns table (
  id uuid, user_id uuid, display_name text, role text, active boolean,
  can_view_shop_sales boolean, max_discount_pct numeric, created_at timestamptz,
  updated_at timestamptz, deactivated_at timestamptz, pin_set boolean, pin_must_change boolean,
  pin_locked_until timestamptz
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  perform public.assert_shop_owner(p_shop_id);
  return query
    select m.id, m.user_id, m.display_name, m.role, m.active, m.can_view_shop_sales,
           m.max_discount_pct, m.created_at, m.updated_at, m.deactivated_at,
           coalesce(p.pin_hash is not null, false), coalesce(p.must_change, false),
           case when p.locked_until > pg_catalog.now() then p.locked_until end
    from public.shop_members m
    left join public.member_pins p on p.member_id = m.id
    where m.shop_id = p_shop_id
    order by m.active desc, m.display_name;
end;
$function$;

-- Réinitialise le PIN d'un membre : PIN effacé, must_change = true, sessions de caisse du membre
-- fermées. Le membre choisira un nouveau PIN à sa prochaine ouverture ; le propriétaire ne le
-- connaît jamais.
create or replace function public.owner_reset_member_pin(p_member_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_member public.shop_members%rowtype;
  v_closed integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into v_member from public.shop_members m where m.id = p_member_id for update;
  if not found or public.shop_role(v_member.shop_id) is distinct from 'owner' then
    raise exception 'Member not found' using errcode = '42501';
  end if;
  insert into public.member_pins (member_id, pin_hash, must_change)
  values (p_member_id, null, true)
  on conflict (member_id) do update
    set pin_hash = null, must_change = true, failed_attempts = 0, locked_until = null;
  update public.till_sessions
  set closed_at = pg_catalog.now()
  where member_id = p_member_id and closed_at is null;
  get diagnostics v_closed = row_count;
  perform public.shop_audit(v_member.shop_id, 'pin_reset', p_member_id::text,
    pg_catalog.jsonb_build_object('display_name', v_member.display_name,
      'till_sessions_closed', v_closed));
  return pg_catalog.jsonb_build_object('id', p_member_id, 'pin_set', false,
    'pin_must_change', true);
end;
$function$;

-- Ouvre une session de caisse sur l'appareil du propriétaire (cas b). Appelant : propriétaire.
-- Retour :
--   {"status": "ok", "token": "<64 hex>", "session_id", "expires_at", "member_id",
--    "display_name", "max_discount_pct"}   le jeton n'est renvoyé qu'ici, une seule fois ;
--   {"status": "invalid", "attempts_left"} | {"status": "locked", "retry_after"} |
--   {"status": "not_set"}                  (le caissier doit d'abord choisir son PIN).
-- Exceptions : 'Authentication required', 'Shop not found', 'Member not found' (42501).
create or replace function public.open_till_session(
  p_shop_id uuid,
  p_member_id uuid,
  p_pin text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c_duration constant interval := interval '12 hours';
  v_member public.shop_members%rowtype;
  v_check jsonb;
  v_token text;
  v_session public.till_sessions%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  select * into v_member from public.shop_members m
  where m.id = p_member_id and m.shop_id = p_shop_id and m.active;
  if not found then
    raise exception 'Member not found' using errcode = '42501';
  end if;
  v_check := public.member_pin_check(v_member.id, p_pin);
  if v_check ->> 'status' <> 'ok' then
    if v_check ->> 'status' in ('invalid', 'locked') then
      perform public.shop_audit(p_shop_id, 'till_session_pin_failed', v_member.id::text,
        pg_catalog.jsonb_build_object('display_name', v_member.display_name,
          'result', v_check ->> 'status'));
    end if;
    return v_check;
  end if;
  v_token := pg_catalog.encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.till_sessions (shop_id, member_id, token_hash, opened_by, expires_at)
  values (p_shop_id, v_member.id,
          pg_catalog.sha256(pg_catalog.convert_to('covi-till:' || v_token, 'UTF8')),
          auth.uid(), pg_catalog.now() + c_duration)
  returning * into v_session;
  perform public.shop_audit(p_shop_id, 'till_session_opened', v_member.id::text,
    pg_catalog.jsonb_build_object('display_name', v_member.display_name,
      'session_id', v_session.id, 'expires_at', v_session.expires_at));
  return pg_catalog.jsonb_build_object('status', 'ok', 'token', v_token,
    'session_id', v_session.id, 'expires_at', v_session.expires_at,
    'member_id', v_member.id, 'display_name', v_member.display_name,
    'max_discount_pct', v_member.max_discount_pct);
end;
$function$;

-- Ferme une session de caisse (changement de caissier, fermeture, déconnexion). Appelant :
-- propriétaire de la boutique de la session. Renvoie true si une session ouverte a été fermée,
-- false si le jeton est inconnu, d'une autre boutique ou déjà fermé (idempotent).
create or replace function public.close_till_session(p_shop_id uuid, p_token text)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_session public.till_sessions%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then
    return false;
  end if;
  update public.till_sessions t
  set closed_at = pg_catalog.now()
  where t.token_hash = pg_catalog.sha256(pg_catalog.convert_to('covi-till:' || p_token, 'UTF8'))
    and t.shop_id = p_shop_id and t.closed_at is null
  returning * into v_session;
  if not found then
    return false;
  end if;
  perform public.shop_audit(p_shop_id, 'till_session_closed', v_session.member_id::text,
    pg_catalog.jsonb_build_object('session_id', v_session.id));
  return true;
end;
$function$;

-- Désactiver un membre ferme aussi ses sessions de caisse (till_session_member refuse déjà un
-- membre inactif : ceci évite qu'une réactivation ne ranime d'anciens jetons).
create or replace function public.shop_members_close_till_sessions()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.active and not new.active then
    update public.till_sessions
    set closed_at = pg_catalog.now()
    where member_id = new.id and closed_at is null;
  end if;
  return new;
end;
$function$;

drop trigger if exists shop_members_close_till_sessions on public.shop_members;
create trigger shop_members_close_till_sessions
  after update of active on public.shop_members
  for each row execute function public.shop_members_close_till_sessions();

-- 6. Droits EXECUTE ------------------------------------------------------------------------------
revoke execute on function public.member_pin_assert_strength(text)
  from public, anon, authenticated;
revoke execute on function public.member_pin_check(uuid, text) from public, anon, authenticated;
revoke execute on function public.assert_active_member(uuid) from public, anon, authenticated;
revoke execute on function public.till_session_member(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.shop_members_close_till_sessions()
  from public, anon, authenticated;

revoke execute on function public.has_shop_permission(uuid, text) from public, anon;
revoke execute on function public.set_my_pin(uuid, text, text) from public, anon;
revoke execute on function public.verify_my_pin(uuid, text) from public, anon;
revoke execute on function public.my_member_shops() from public, anon;
revoke execute on function public.list_shop_members(uuid) from public, anon;
revoke execute on function public.owner_reset_member_pin(uuid) from public, anon;
revoke execute on function public.open_till_session(uuid, uuid, text) from public, anon;
revoke execute on function public.close_till_session(uuid, text) from public, anon;
grant execute on function public.has_shop_permission(uuid, text) to authenticated;
grant execute on function public.set_my_pin(uuid, text, text) to authenticated;
grant execute on function public.verify_my_pin(uuid, text) to authenticated;
grant execute on function public.my_member_shops() to authenticated;
grant execute on function public.list_shop_members(uuid) to authenticated;
grant execute on function public.owner_reset_member_pin(uuid) to authenticated;
grant execute on function public.open_till_session(uuid, uuid, text) to authenticated;
grant execute on function public.close_till_session(uuid, text) to authenticated;
