-- Caisse multi-caissiers (1/2) : équipe de la boutique, invitations, journal d'audit.
--
-- Modèle :
--   - le PROPRIÉTAIRE reste défini par shops.owner_id (non dupliqué ici) ;
--   - un CAISSIER est une ligne de shop_members (rôle 'cashier', seul rôle en V1), rattachée à
--     son PROPRE compte Supabase Auth. Il rejoint la boutique avec un code d'invitation à usage
--     unique créé par le propriétaire ;
--   - permissions du caissier : vendre et lire le stock (toujours, s'il est actif), voir toutes
--     les ventes de la boutique (can_view_shop_sales, sinon seulement les siennes), remise
--     maximale autorisée en % du prix affiché (max_discount_pct, 0 par défaut = aucune remise) ;
--   - aucune écriture directe par le client : tout passe par des fonctions SECURITY DEFINER
--     (search_path vide, auth.uid() vérifié, propriétaire ou membre actif vérifié) ;
--   - chaque action de gestion d'équipe écrit dans shop_audit_log (lecture : propriétaire seul).
--
-- Codes d'invitation : 12 caractères (alphabet sans 0/O, 1/I/L, U : ≈ 59 bits d'aléa tiré de
-- gen_random_uuid(), générateur cryptographique de PostgreSQL), affichés une seule fois au
-- propriétaire, stockés uniquement sous forme d'empreinte SHA-256 (pg_catalog.sha256, natif
-- depuis PostgreSQL 11 : aucune dépendance à pgcrypto ni au schéma `extensions`). Validité 48 h,
-- usage unique, révocables. Tentatives limitées : 5 échecs par utilisateur sur 15 minutes.
--
-- Migration non destructive : uniquement des créations (tables, fonctions, politiques).
-- Idempotente : `if not exists`, `create or replace`, `drop policy if exists` avant création.

-- 1. Tables ----------------------------------------------------------------------------------

create table if not exists public.shop_members (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'cashier' check (role in ('cashier')),
  active boolean not null default true,
  can_view_shop_sales boolean not null default false,
  max_discount_pct numeric(5,2) not null default 0
    check (max_discount_pct >= 0 and max_discount_pct <= 100),
  display_name text not null
    check (char_length(pg_catalog.btrim(display_name)) between 1 and 60),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deactivated_at timestamptz,
  constraint shop_members_shop_user_key unique (shop_id, user_id),
  constraint shop_members_deactivated_check check (active or deactivated_at is not null)
);
create index if not exists shop_members_user_idx on public.shop_members (user_id);

create table if not exists public.shop_member_invites (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  code_hash bytea not null unique,
  display_name text not null
    check (char_length(pg_catalog.btrim(display_name)) between 1 and 60),
  can_view_shop_sales boolean not null default false,
  max_discount_pct numeric(5,2) not null default 0
    check (max_discount_pct >= 0 and max_discount_pct <= 100),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id) on delete set null,
  revoked_at timestamptz,
  constraint shop_member_invites_redeemed_check
    check (redeemed_by is null or redeemed_at is not null)
);
create index if not exists shop_member_invites_shop_idx on public.shop_member_invites (shop_id);

-- Tentatives d'utilisation d'un code (limitation du nombre d'essais).
create table if not exists public.shop_member_invite_attempts (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  succeeded boolean not null,
  attempted_at timestamptz not null default now()
);
create index if not exists shop_member_invite_attempts_user_idx
  on public.shop_member_invite_attempts (user_id, attempted_at desc);

create table if not exists public.shop_audit_log (
  id bigint generated always as identity primary key,
  shop_id uuid not null references public.shops(id) on delete cascade,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  target text,
  details jsonb not null default '{}'::jsonb,
  at timestamptz not null default now()
);
create index if not exists shop_audit_log_shop_at_idx on public.shop_audit_log (shop_id, at desc);

-- 2. Règles de cohérence ------------------------------------------------------------------------

-- Le propriétaire n'est jamais membre de sa propre boutique (son rôle vient de shops.owner_id).
create or replace function public.shop_members_check_not_owner()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if exists (
    select 1 from public.shops s where s.id = new.shop_id and s.owner_id = new.user_id
  ) then
    raise exception 'Owner cannot be a member of own shop' using errcode = '23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists shop_members_check_not_owner on public.shop_members;
create trigger shop_members_check_not_owner
  before insert or update of shop_id, user_id on public.shop_members
  for each row execute function public.shop_members_check_not_owner();

drop trigger if exists shop_members_touch_updated_at on public.shop_members;
create trigger shop_members_touch_updated_at
  before update on public.shop_members
  for each row execute function public.touch_updated_at();

-- 3. Fonctions d'autorisation (utilisées par les politiques et les RPC) ------------------------
-- SECURITY DEFINER : elles lisent shops et shop_members sans dépendre de la RLS de l'appelant
-- (évite les récursions de politiques) mais ne renseignent QUE sur l'appelant (auth.uid()).

-- 'owner', 'cashier' (membre ACTIF) ou NULL.
create or replace function public.shop_role(p_shop_id uuid)
returns text
language sql
stable
security definer
set search_path to ''
as $function$
  select case
    when exists (
      select 1 from public.shops s where s.id = p_shop_id and s.owner_id = auth.uid()
    ) then 'owner'
    when exists (
      select 1 from public.shop_members m
      where m.shop_id = p_shop_id and m.user_id = auth.uid() and m.active
    ) then 'cashier'
  end
$function$;

-- Permissions : 'manage' (propriétaire seul), 'sell' et 'view_products' (propriétaire ou membre
-- actif), 'view_shop_sales' (propriétaire, ou membre actif avec can_view_shop_sales).
-- Une permission inconnue vaut false.
create or replace function public.has_shop_permission(p_shop_id uuid, p_permission text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    exists (select 1 from public.shops s where s.id = p_shop_id and s.owner_id = auth.uid())
      and p_permission in ('manage', 'sell', 'view_products', 'view_shop_sales')
    or exists (
      select 1 from public.shop_members m
      where m.shop_id = p_shop_id and m.user_id = auth.uid() and m.active
        and (p_permission in ('sell', 'view_products')
             or (p_permission = 'view_shop_sales' and m.can_view_shop_sales))
    ),
    false)
$function$;

-- Boutiques où l'appelant est MEMBRE ACTIF avec la permission demandée (hors propriétaire :
-- les politiques propriétaires existantes restent en place). Forme ensembliste pour les
-- politiques : `shop_id in (select public.member_shop_ids('…'))` est évalué une fois par
-- requête, pas une fois par ligne.
create or replace function public.member_shop_ids(p_permission text)
returns setof uuid
language sql
stable
security definer
set search_path to ''
as $function$
  select m.shop_id
  from public.shop_members m
  where m.user_id = auth.uid() and m.active
    and (p_permission in ('sell', 'view_products')
         or (p_permission = 'view_shop_sales' and m.can_view_shop_sales))
$function$;

-- 4. RLS ---------------------------------------------------------------------------------------
alter table public.shop_members enable row level security;
alter table public.shop_member_invites enable row level security;
alter table public.shop_member_invite_attempts enable row level security;
alter table public.shop_audit_log enable row level security;

-- shop_members : le propriétaire lit son équipe ; un membre ne lit que SA ligne. Aucune
-- politique d'écriture : les écritures passent par les RPC ci-dessous.
drop policy if exists shop_members_owner_select on public.shop_members;
create policy shop_members_owner_select on public.shop_members for select to authenticated
  using (exists (
    select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())
  ));
drop policy if exists shop_members_self_select on public.shop_members;
create policy shop_members_self_select on public.shop_members for select to authenticated
  using (user_id = (select auth.uid()));

-- Journal : propriétaire seul, lecture seule.
drop policy if exists shop_audit_log_owner_select on public.shop_audit_log;
create policy shop_audit_log_owner_select on public.shop_audit_log for select to authenticated
  using (exists (
    select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())
  ));

-- Invitations et tentatives : aucune politique (RLS active = aucun accès direct). Lecture des
-- invitations en attente par list_member_invites, jamais de l'empreinte.

-- 5. Privilèges --------------------------------------------------------------------------------
revoke all on public.shop_members, public.shop_member_invites, public.shop_member_invite_attempts,
  public.shop_audit_log from public, anon, authenticated;
grant select on public.shop_members, public.shop_audit_log to authenticated;
revoke all on sequence public.shop_member_invite_attempts_id_seq, public.shop_audit_log_id_seq
  from public, anon, authenticated;

-- 6. Outils internes ---------------------------------------------------------------------------

-- Forme canonique d'un code saisi : majuscules, sans espaces ni tirets.
create or replace function public.member_invite_normalize(p_code text)
returns text
language sql
immutable
set search_path to ''
as $function$
  select pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'))
$function$;

create or replace function public.member_invite_hash(p_code text)
returns bytea
language sql
immutable
set search_path to ''
as $function$
  select pg_catalog.sha256(pg_catalog.convert_to('covi-invite:' || p_code, 'UTF8'))
$function$;

create or replace function public.shop_audit(
  p_shop_id uuid, p_action text, p_target text, p_details jsonb
)
returns void
language sql
security definer
set search_path to ''
as $function$
  insert into public.shop_audit_log (shop_id, actor_id, action, target, details)
  values (p_shop_id, auth.uid(), p_action, p_target, coalesce(p_details, '{}'::jsonb))
$function$;

-- Vérifie la session et le propriétaire ; lève 42501 sinon.
create or replace function public.assert_shop_owner(p_shop_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_shop_id is null or not exists (
    select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_uid
  ) then
    raise exception 'Shop not found' using errcode = '42501';
  end if;
  return v_uid;
end;
$function$;

-- 7. RPC de gestion de l'équipe (propriétaire) -------------------------------------------------

-- Crée une invitation et renvoie le code EN CLAIR, une seule fois.
-- Retour : {"invite_id", "code" ("ABCD-EFGH-JKMN"), "display_name", "expires_at",
--           "can_view_shop_sales", "max_discount_pct"}
create or replace function public.create_member_invite(
  p_shop_id uuid,
  p_display_name text,
  p_can_view_shop_sales boolean default false,
  p_max_discount_pct numeric default 0
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c_alphabet constant text := 'ABCDEFGHJKMNPQRSTVWXYZ23456789';
  v_name text := pg_catalog.btrim(p_display_name);
  v_pct numeric := coalesce(p_max_discount_pct, 0);
  v_bytes bytea;
  v_byte integer;
  v_code text := '';
  v_invite public.shop_member_invites%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  if v_name is null or char_length(v_name) not between 1 and 60 or v_name ~ '[[:cntrl:]]' then
    raise exception 'Invalid display name';
  end if;
  if v_pct < 0 or v_pct > 100 then
    raise exception 'Invalid discount';
  end if;
  if (select count(*) from public.shop_member_invites i
      where i.shop_id = p_shop_id and i.redeemed_at is null and i.revoked_at is null
        and i.expires_at > now()) >= 20 then
    raise exception 'Too many pending invites';
  end if;

  -- 12 caractères tirés de l'alphabet par rejet (pas de biais modulo).
  while char_length(v_code) < 12 loop
    v_bytes := pg_catalog.uuid_send(pg_catalog.gen_random_uuid());
    for i in 0 .. 15 loop
      -- octets 6 et 8 : bits de version et de variante, non aléatoires
      continue when i in (6, 8);
      v_byte := pg_catalog.get_byte(v_bytes, i);
      continue when v_byte >= 240;
      v_code := v_code || pg_catalog.substr(c_alphabet, (v_byte % 30) + 1, 1);
      exit when char_length(v_code) = 12;
    end loop;
  end loop;

  insert into public.shop_member_invites (
    shop_id, code_hash, display_name, can_view_shop_sales, max_discount_pct, created_by,
    expires_at)
  values (p_shop_id, public.member_invite_hash(v_code), v_name,
          coalesce(p_can_view_shop_sales, false), v_pct, auth.uid(), now() + interval '48 hours')
  returning * into v_invite;

  perform public.shop_audit(p_shop_id, 'invite_created', v_invite.id::text,
    pg_catalog.jsonb_build_object('display_name', v_name,
      'can_view_shop_sales', v_invite.can_view_shop_sales,
      'max_discount_pct', v_invite.max_discount_pct, 'expires_at', v_invite.expires_at));

  return pg_catalog.jsonb_build_object(
    'invite_id', v_invite.id,
    'code', pg_catalog.substr(v_code, 1, 4) || '-' || pg_catalog.substr(v_code, 5, 4) || '-'
            || pg_catalog.substr(v_code, 9, 4),
    'display_name', v_invite.display_name,
    'expires_at', v_invite.expires_at,
    'can_view_shop_sales', v_invite.can_view_shop_sales,
    'max_discount_pct', v_invite.max_discount_pct);
end;
$function$;

-- Invitations encore utilisables (ni utilisées, ni révoquées, ni expirées). Jamais l'empreinte.
create or replace function public.list_member_invites(p_shop_id uuid)
returns table (
  id uuid, display_name text, can_view_shop_sales boolean, max_discount_pct numeric,
  created_at timestamptz, expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
begin
  perform public.assert_shop_owner(p_shop_id);
  return query
    select i.id, i.display_name, i.can_view_shop_sales, i.max_discount_pct, i.created_at,
           i.expires_at
    from public.shop_member_invites i
    where i.shop_id = p_shop_id and i.redeemed_at is null and i.revoked_at is null
      and i.expires_at > now()
    order by i.created_at desc;
end;
$function$;

create or replace function public.revoke_member_invite(p_invite_id uuid)
returns boolean
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_invite public.shop_member_invites%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  select * into v_invite from public.shop_member_invites i where i.id = p_invite_id for update;
  if not found or public.shop_role(v_invite.shop_id) is distinct from 'owner' then
    raise exception 'Invite not found' using errcode = '42501';
  end if;
  if v_invite.redeemed_at is not null then
    raise exception 'Invite already used';
  end if;
  if v_invite.revoked_at is null then
    update public.shop_member_invites set revoked_at = now() where id = p_invite_id;
    perform public.shop_audit(v_invite.shop_id, 'invite_revoked', p_invite_id::text,
      pg_catalog.jsonb_build_object('display_name', v_invite.display_name));
  end if;
  return true;
end;
$function$;

-- Équipe de la boutique (propriétaire seul).
create or replace function public.list_shop_members(p_shop_id uuid)
returns table (
  id uuid, user_id uuid, display_name text, role text, active boolean,
  can_view_shop_sales boolean, max_discount_pct numeric, created_at timestamptz,
  updated_at timestamptz, deactivated_at timestamptz
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
           m.max_discount_pct, m.created_at, m.updated_at, m.deactivated_at
    from public.shop_members m
    where m.shop_id = p_shop_id
    order by m.active desc, m.display_name;
end;
$function$;

-- Active ou désactive un membre. L'historique (ventes, journal) est conservé.
create or replace function public.set_member_active(p_member_id uuid, p_active boolean)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_member public.shop_members%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_active is null then raise exception 'Invalid state'; end if;
  select * into v_member from public.shop_members m where m.id = p_member_id for update;
  if not found or public.shop_role(v_member.shop_id) is distinct from 'owner' then
    raise exception 'Member not found' using errcode = '42501';
  end if;
  if v_member.active is distinct from p_active then
    update public.shop_members
    set active = p_active,
        deactivated_at = case when p_active then null else now() end
    where id = p_member_id
    returning * into v_member;
    perform public.shop_audit(v_member.shop_id,
      case when p_active then 'member_reactivated' else 'member_deactivated' end,
      p_member_id::text, pg_catalog.jsonb_build_object('display_name', v_member.display_name));
  end if;
  return pg_catalog.jsonb_build_object('id', v_member.id, 'active', v_member.active,
    'deactivated_at', v_member.deactivated_at);
end;
$function$;

create or replace function public.set_member_permissions(
  p_member_id uuid,
  p_can_view_shop_sales boolean,
  p_max_discount_pct numeric
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_member public.shop_members%rowtype;
  v_before jsonb;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_can_view_shop_sales is null then raise exception 'Invalid state'; end if;
  if p_max_discount_pct is null or p_max_discount_pct < 0 or p_max_discount_pct > 100 then
    raise exception 'Invalid discount';
  end if;
  select * into v_member from public.shop_members m where m.id = p_member_id for update;
  if not found or public.shop_role(v_member.shop_id) is distinct from 'owner' then
    raise exception 'Member not found' using errcode = '42501';
  end if;
  v_before := pg_catalog.jsonb_build_object('can_view_shop_sales', v_member.can_view_shop_sales,
    'max_discount_pct', v_member.max_discount_pct);
  update public.shop_members
  set can_view_shop_sales = p_can_view_shop_sales,
      max_discount_pct = p_max_discount_pct
  where id = p_member_id
  returning * into v_member;
  perform public.shop_audit(v_member.shop_id, 'member_permissions_changed', p_member_id::text,
    pg_catalog.jsonb_build_object('display_name', v_member.display_name, 'before', v_before,
      'after', pg_catalog.jsonb_build_object('can_view_shop_sales', v_member.can_view_shop_sales,
        'max_discount_pct', v_member.max_discount_pct)));
  return pg_catalog.jsonb_build_object('id', v_member.id,
    'can_view_shop_sales', v_member.can_view_shop_sales,
    'max_discount_pct', v_member.max_discount_pct);
end;
$function$;

-- 8. RPC du caissier ---------------------------------------------------------------------------

-- Utilise un code d'invitation. Ne lève PAS d'exception pour un mauvais code : la tentative
-- doit être enregistrée (une exception annulerait l'écriture). Retour :
--   {"status": "joined", "member_id", "shop_id", "shop_name", "display_name"}
--   {"status": "invalid"}   code inconnu, expiré, déjà utilisé ou révoqué (indistinguables)
--   {"status": "locked", "retry_after"}   5 échecs ou plus sur les 15 dernières minutes
-- Exceptions : 'Authentication required' (42501), 'Owner cannot join own shop'.
create or replace function public.redeem_member_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c_max_failures constant integer := 5;
  c_window constant interval := interval '15 minutes';
  v_uid uuid := auth.uid();
  v_code text := public.member_invite_normalize(p_code);
  v_failures integer;
  v_oldest timestamptz;
  v_invite public.shop_member_invites%rowtype;
  v_member public.shop_members%rowtype;
  v_shop_name text;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  -- Sérialise les essais d'un même utilisateur (pas de contournement par appels parallèles).
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('covi-invite-attempts:' || v_uid::text, 0));
  select count(*), min(a.attempted_at) into v_failures, v_oldest
  from public.shop_member_invite_attempts a
  where a.user_id = v_uid and not a.succeeded and a.attempted_at > now() - c_window;
  if v_failures >= c_max_failures then
    return pg_catalog.jsonb_build_object('status', 'locked', 'retry_after', v_oldest + c_window);
  end if;

  if char_length(v_code) = 12 then
    select * into v_invite from public.shop_member_invites i
    where i.code_hash = public.member_invite_hash(v_code)
    for update;
  end if;
  if v_invite.id is null or v_invite.redeemed_at is not null or v_invite.revoked_at is not null
     or v_invite.expires_at <= now() then
    insert into public.shop_member_invite_attempts (user_id, succeeded) values (v_uid, false);
    return pg_catalog.jsonb_build_object('status', 'invalid');
  end if;
  if exists (select 1 from public.shops s where s.id = v_invite.shop_id and s.owner_id = v_uid)
  then
    raise exception 'Owner cannot join own shop';
  end if;

  insert into public.shop_members (shop_id, user_id, role, active, can_view_shop_sales,
                                   max_discount_pct, display_name, created_by)
  values (v_invite.shop_id, v_uid, 'cashier', true, v_invite.can_view_shop_sales,
          v_invite.max_discount_pct, v_invite.display_name, v_invite.created_by)
  on conflict (shop_id, user_id) do update
    set active = true, deactivated_at = null,
        can_view_shop_sales = excluded.can_view_shop_sales,
        max_discount_pct = excluded.max_discount_pct,
        display_name = excluded.display_name
  returning * into v_member;
  update public.shop_member_invites
  set redeemed_at = now(), redeemed_by = v_uid
  where id = v_invite.id;
  insert into public.shop_member_invite_attempts (user_id, succeeded) values (v_uid, true);
  perform public.shop_audit(v_invite.shop_id, 'member_joined', v_member.id::text,
    pg_catalog.jsonb_build_object('display_name', v_member.display_name,
      'invite_id', v_invite.id, 'can_view_shop_sales', v_member.can_view_shop_sales,
      'max_discount_pct', v_member.max_discount_pct));

  select s.name into v_shop_name from public.shops s where s.id = v_invite.shop_id;
  return pg_catalog.jsonb_build_object('status', 'joined', 'member_id', v_member.id,
    'shop_id', v_invite.shop_id, 'shop_name', v_shop_name,
    'display_name', v_member.display_name);
end;
$function$;

-- Boutiques où l'appelant est membre ACTIF, avec ses propres permissions. Seules des colonnes
-- sûres de shops sont exposées (pas owner_id, pas de coordonnées GPS).
create or replace function public.my_member_shops()
returns table (
  member_id uuid, shop_id uuid, shop_name text, shop_city text, shop_country text,
  shop_currency text, display_name text, role text, can_view_shop_sales boolean,
  max_discount_pct numeric
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
           m.can_view_shop_sales, m.max_discount_pct
    from public.shop_members m
    join public.shops s on s.id = m.shop_id
    where m.user_id = auth.uid() and m.active
    order by s.name;
end;
$function$;

-- 9. Droits EXECUTE ------------------------------------------------------------------------------
-- Aucun accès anonyme. Les fonctions internes ne sont exécutables par aucun rôle d'API.
revoke execute on function public.shop_members_check_not_owner() from public, anon, authenticated;
revoke execute on function public.member_invite_normalize(text) from public, anon, authenticated;
revoke execute on function public.member_invite_hash(text) from public, anon, authenticated;
revoke execute on function public.shop_audit(uuid, text, text, jsonb)
  from public, anon, authenticated;
revoke execute on function public.assert_shop_owner(uuid) from public, anon, authenticated;

-- Les fonctions d'autorisation sont appelées par les politiques RLS avec les droits de
-- l'utilisateur : authenticated doit pouvoir les exécuter. Elles ne renseignent que sur lui.
revoke execute on function public.shop_role(uuid) from public, anon;
revoke execute on function public.has_shop_permission(uuid, text) from public, anon;
revoke execute on function public.member_shop_ids(text) from public, anon;
grant execute on function public.shop_role(uuid) to authenticated;
grant execute on function public.has_shop_permission(uuid, text) to authenticated;
grant execute on function public.member_shop_ids(text) to authenticated;

revoke execute on function public.create_member_invite(uuid, text, boolean, numeric)
  from public, anon;
revoke execute on function public.list_member_invites(uuid) from public, anon;
revoke execute on function public.revoke_member_invite(uuid) from public, anon;
revoke execute on function public.list_shop_members(uuid) from public, anon;
revoke execute on function public.set_member_active(uuid, boolean) from public, anon;
revoke execute on function public.set_member_permissions(uuid, boolean, numeric)
  from public, anon;
revoke execute on function public.redeem_member_invite(text) from public, anon;
revoke execute on function public.my_member_shops() from public, anon;
grant execute on function public.create_member_invite(uuid, text, boolean, numeric)
  to authenticated;
grant execute on function public.list_member_invites(uuid) to authenticated;
grant execute on function public.revoke_member_invite(uuid) to authenticated;
grant execute on function public.list_shop_members(uuid) to authenticated;
grant execute on function public.set_member_active(uuid, boolean) to authenticated;
grant execute on function public.set_member_permissions(uuid, boolean, numeric) to authenticated;
grant execute on function public.redeem_member_invite(text) to authenticated;
grant execute on function public.my_member_shops() to authenticated;
