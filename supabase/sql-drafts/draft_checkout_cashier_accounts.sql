-- COVI: REVIEW-ONLY cashier accounts and PIN authorization. Never apply to live DB
-- before owner approval, security audit and native Supabase verification.
-- Must run AFTER checkout order schema and BEFORE checkout RPC definitions.
begin;
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- No cashier credentials in shop/user metadata or rows exposed to PostgREST.
create table if not exists public.checkout_cashiers (
  shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  first_name text not null check (length(first_name) between 1 and 60),
  active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (shop_id,user_id)
);
create table if not exists public.checkout_cashier_secrets (
  shop_id uuid not null,
  user_id uuid not null,
  pin_hash text not null,
  failed_attempts integer not null default 0 check (failed_attempts between 0 and 5),
  blocked_until timestamptz,
  primary key(shop_id,user_id),
  foreign key (shop_id,user_id) references public.checkout_cashiers(shop_id,user_id) on delete cascade
);
create table if not exists public.checkout_cashier_invites (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  token_hash text not null unique,
  first_name text not null check (length(first_name) between 1 and 60),
  created_by uuid not null references auth.users(id),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (redeemed_at is null or redeemed_by is not null)
);

alter table public.checkout_cashiers enable row level security;
alter table public.checkout_cashier_secrets enable row level security;
alter table public.checkout_cashier_invites enable row level security;
-- Only non-secret membership metadata may be read, and only by the
-- member or owner. NO browser writes to any checkout account table.
create policy "cashier and shop owner read membership"
  on public.checkout_cashiers for select to authenticated
  using (user_id = (select auth.uid()) or exists (
    select 1 from public.shops s
    where s.id = shop_id and s.owner_id = (select auth.uid())
  ));
revoke all on public.checkout_cashier_secrets, public.checkout_cashier_invites
  from public, anon, authenticated;
revoke insert, update, delete on public.checkout_cashiers from anon, authenticated;
revoke select on public.checkout_cashier_secrets, public.checkout_cashier_invites
  from authenticated;

-- Owner creates one-use short-lived invitation. Share this code privately
-- with the employee, who signs into their OWN COVI Auth account.
create or replace function public.create_checkout_cashier_invite(
  p_shop_id uuid, p_first_name text
) returns jsonb language plpgsql security definer set search_path = ''
as $fn$
declare v_actor uuid := (select auth.uid());
  v_name text := pg_catalog.btrim(p_first_name);
  v_token uuid := pg_catalog.gen_random_uuid();
  v_expiry timestamptz := now() + interval '48 hours';
begin
  if v_actor is null then raise exception 'Connexion requise' using errcode='28000'; end if;
  if not exists (select 1 from public.shops s where s.id=p_shop_id and s.owner_id=v_actor) then
    raise exception 'Propriétaire requis' using errcode='42501';
  end if;
  if v_name is null or length(v_name) not between 1 and 60 or
     v_name ~ '[[:cntrl:]<>0-9]' then
    raise exception 'Prénom du caissier invalide';
  end if;
  insert into public.checkout_cashier_invites(shop_id,token_hash,first_name,created_by,expires_at)
  values (p_shop_id, pg_catalog.encode(extensions.digest(v_token::text,'sha256'),'hex'),
    v_name,v_actor,v_expiry);
  return jsonb_build_object('inviteCode',v_token,'firstName',v_name,'expiresAt',v_expiry);
end;
$fn$;

-- A registered, authenticated staff user voluntarily joins ONLY the shop
-- named by the one-use invitation. No lookup of arbitrary emails.
create or replace function public.redeem_checkout_cashier_invite(p_invite_code uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $fn$
declare v_actor uuid := (select auth.uid());
  v_inv public.checkout_cashier_invites%rowtype; v_shop_name text;
begin
  if v_actor is null then raise exception 'Connexion requise' using errcode='28000'; end if;
  select * into v_inv from public.checkout_cashier_invites i
    where i.token_hash=pg_catalog.encode(extensions.digest(p_invite_code::text,'sha256'),'hex')
    for update;
  if not found or v_inv.redeemed_at is not null or v_inv.expires_at < now() then
    raise exception 'Invitation invalide ou expirée';
  end if;
  if exists(select 1 from public.shops s where s.id=v_inv.shop_id and s.owner_id=v_actor) then
    raise exception 'Le propriétaire ne rejoint pas son propre personnel';
  end if;
  insert into public.checkout_cashiers(shop_id,user_id,first_name,active,created_by)
  values (v_inv.shop_id,v_actor,v_inv.first_name,true,v_inv.created_by)
  on conflict (shop_id,user_id) do update set active=true,
      first_name=excluded.first_name;
  update public.checkout_cashier_invites
    set redeemed_at=now(),redeemed_by=v_actor where id=v_inv.id;
  select name into v_shop_name from public.shops where id=v_inv.shop_id;
  return jsonb_build_object('shopId',v_inv.shop_id,'shopName',v_shop_name,'firstName',v_inv.first_name);
end;
$fn$;

-- The owner may disable/re-enable the account at any time. Does not delete history.
create or replace function public.set_checkout_cashier_active(
  p_shop_id uuid,p_cashier_user_id uuid,p_active boolean
) returns boolean language plpgsql security definer set search_path = ''
as $fn$
begin
  if (select auth.uid()) is null then raise exception 'Connexion requise' using errcode='28000'; end if;
  if not exists(select 1 from public.shops s where s.id=p_shop_id and s.owner_id=(select auth.uid())) then
    raise exception 'Propriétaire requis' using errcode='42501';
  end if;
  if p_active is null then raise exception 'État invalide'; end if;
  update public.checkout_cashiers set active=p_active
    where shop_id=p_shop_id and user_id=p_cashier_user_id;
  if not found then raise exception 'Caissier introuvable'; end if;
  return true;
end;
$fn$;

-- Sanitized owner-facing list: NEVER return PIN hashes or invitation digests.
create or replace function public.list_checkout_cashiers(p_shop_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $fn$
declare v_staff jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Connexion requise' using errcode='28000'; end if;
  if not exists(select 1 from public.shops s where s.id=p_shop_id and s.owner_id=(select auth.uid())) then
    raise exception 'Propriétaire requis' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'userId',c.user_id,'firstName',c.first_name,'active',c.active,
    'pinConfigured',sp.user_id is not null
  ) order by c.created_at),'[]'::jsonb) into v_staff
  from public.checkout_cashiers c
  left join public.checkout_cashier_secrets sp
    on sp.shop_id=c.shop_id and sp.user_id=c.user_id
  where c.shop_id=p_shop_id;
  return v_staff;
end;
$fn$;

-- Staff portal discovers only memberships tied to this authenticated user.
create or replace function public.get_my_checkout_cashier_shops()
returns jsonb language plpgsql security definer set search_path = ''
as $fn$
declare v_shops jsonb;
begin
  if (select auth.uid()) is null then raise exception 'Connexion requise' using errcode='28000'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'shopId',c.shop_id,'shopName',s.name,'firstName',c.first_name,
    'pinConfigured',sp.user_id is not null
  ) order by c.created_at),'[]'::jsonb) into v_shops
  from public.checkout_cashiers c
  join public.shops s on s.id=c.shop_id
  left join public.checkout_cashier_secrets sp on
    sp.shop_id=c.shop_id and sp.user_id=c.user_id
  where c.user_id=(select auth.uid()) and c.active=true;
  return v_shops;
end;
$fn$;

-- A personal PIN of 6-8 digits is bcrypt-hashed with an independent salt.
-- Current PIN is mandatory for changing an existing PIN.
create or replace function public.set_checkout_cashier_pin(
  p_shop_id uuid,p_new_pin text,p_current_pin text default null
) returns boolean language plpgsql security definer set search_path = ''
as $fn$
declare v_actor uuid := (select auth.uid());
  v_old public.checkout_cashier_secrets%rowtype;
  v_owner boolean;
begin
  if v_actor is null then raise exception 'Connexion requise' using errcode='28000'; end if;
  select exists(select 1 from public.shops s where s.id=p_shop_id and s.owner_id=v_actor)
    into v_owner;
  if not v_owner and not exists(
    select 1 from public.checkout_cashiers c
    where c.shop_id=p_shop_id and c.user_id=v_actor and c.active=true
  ) then raise exception 'Caissier non autorisé' using errcode='42501'; end if;
  if p_new_pin is null or p_new_pin !~ '^[0-9]{6,8}$' then
    raise exception 'Code personnel : 6 à 8 chiffres requis';
  end if;
  -- The owner may also use a PIN; owner account is authenticated separately.
  -- Secret FK requires membership: create an owner cashier row when enrolling.
  if v_owner then
    insert into public.checkout_cashiers(shop_id,user_id,first_name,created_by)
      values (p_shop_id,v_actor,'Propriétaire',v_actor)
    on conflict (shop_id,user_id) do nothing;
  end if;
  select * into v_old from public.checkout_cashier_secrets
    where shop_id=p_shop_id and user_id=v_actor for update;
  if found then
    if v_old.blocked_until > now() then return false; end if;
    if p_current_pin is null or p_current_pin !~ '^[0-9]{6,8}$' or
      extensions.crypt(p_current_pin,v_old.pin_hash) <> v_old.pin_hash then
      update public.checkout_cashier_secrets set
        failed_attempts=least(5,failed_attempts+1),
        blocked_until=case when failed_attempts>=4 then now()+interval '15 minutes'
          else null end where shop_id=p_shop_id and user_id=v_actor;
      return false;
    end if;
  end if;
  insert into public.checkout_cashier_secrets(shop_id,user_id,pin_hash)
    values (p_shop_id,v_actor,extensions.crypt(p_new_pin,extensions.gen_salt('bf',10)))
  on conflict (shop_id,user_id) do update set
    pin_hash=excluded.pin_hash,failed_attempts=0,blocked_until=null;
  return true;
end;
$fn$;

-- INTERNAL ONLY: called from confirm RPC, never executable directly by clients.
-- On incorrect PIN, return false instead of throwing so the rate-limit update
-- survives the PostgreSQL transaction commit.
create or replace function public.checkout_cashier_pin_ok(
  p_shop_id uuid,p_user_id uuid,p_pin text,p_allow_legacy_owner boolean default false
) returns boolean language plpgsql security definer set search_path = ''
as $fn$
declare v_pin public.checkout_cashier_secrets%rowtype;
begin
  select * into v_pin from public.checkout_cashier_secrets
    where shop_id=p_shop_id and user_id=p_user_id for update;
  if not found then return p_allow_legacy_owner; end if;
  if v_pin.blocked_until > now() then return false; end if;
  if p_pin is null or p_pin !~ '^[0-9]{6,8}$' or
    extensions.crypt(p_pin,v_pin.pin_hash) <> v_pin.pin_hash then
    update public.checkout_cashier_secrets set
      failed_attempts=least(5,failed_attempts+1),
      blocked_until=case when failed_attempts>=4 then now()+interval '15 minutes'
        else null end
      where shop_id=p_shop_id and user_id=p_user_id;
    return false;
  end if;
  update public.checkout_cashier_secrets set failed_attempts=0,blocked_until=null
    where shop_id=p_shop_id and user_id=p_user_id;
  return true;
end;
$fn$;

-- All browser roles are denied internal verifier. Every exposed management RPC
-- requires auth.uid() AND owner or active-member checks server-side.
revoke all on function public.checkout_cashier_pin_ok(uuid,uuid,text,boolean)
  from public,anon,authenticated;
do $grant$
begin
  -- In local Supabase, service_role may already be available.
  null;
end;
$grant$;
revoke all on function public.create_checkout_cashier_invite(uuid,text) from public,anon;
revoke all on function public.redeem_checkout_cashier_invite(uuid) from public,anon;
revoke all on function public.list_checkout_cashiers(uuid) from public,anon;
revoke all on function public.get_my_checkout_cashier_shops() from public,anon;
revoke all on function public.set_checkout_cashier_active(uuid,uuid,boolean) from public,anon;
revoke all on function public.set_checkout_cashier_pin(uuid,text,text) from public,anon;
grant execute on function public.create_checkout_cashier_invite(uuid,text),
  public.redeem_checkout_cashier_invite(uuid),
  public.list_checkout_cashiers(uuid),
  public.get_my_checkout_cashier_shops(),
  public.set_checkout_cashier_active(uuid,uuid,boolean),
  public.set_checkout_cashier_pin(uuid,text,text) to authenticated;
commit;
