-- COVI multisector v1: owned restaurant catalog/tables and salon services/requests.
-- STAGED ONLY; apply on a throwaway test database before production authorization.
-- This migration depends on 20261017124500_covi_multisector_staff_foundation.sql.

create table public.restaurant_tables (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  label text not null check (char_length(btrim(label)) between 1 and 40),
  zone text not null default 'Salle principale' check (char_length(btrim(zone)) between 1 and 80),
  capacity integer not null default 2 check (capacity between 1 and 50),
  pos_x integer not null default 0 check (pos_x between 0 and 100),
  pos_y integer not null default 0 check (pos_y between 0 and 100),
  qr_token text not null unique default (replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (shop_id, label),
  unique (shop_id, id)
);
create table public.restaurant_menu_items (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 2 and 120),
  category text not null check (char_length(btrim(category)) between 2 and 60),
  kind text not null check (kind in ('dish','drink','dessert')),
  price_xaf bigint not null check (price_xaf between 0 and 1000000000),
  available boolean not null default true,
  drink_stock integer check (drink_stock between 0 and 1000000),
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  constraint drink_stock_only_for_drinks check (
    (kind = 'drink' and drink_stock is not null)
    or (kind <> 'drink' and drink_stock is null)
  )
);
create table public.salon_services (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 2 and 120),
  price_xaf bigint not null check (price_xaf between 0 and 1000000000),
  duration_minutes integer not null check (duration_minutes between 5 and 720),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (shop_id, id)
);
create table public.salon_booking_links (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  public_token text not null unique default (replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '')),
  enabled boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.salon_booking_requests (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  service_id uuid null,
  first_name text not null check (char_length(btrim(first_name)) between 1 and 80),
  last_name text not null check (char_length(btrim(last_name)) between 1 and 80),
  phone text not null check (char_length(btrim(phone)) between 6 and 25),
  requested_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','confirmed','declined','cancelled','completed','no_show')),
  created_at timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, service_id) references public.salon_services (shop_id, id)
);
create index restaurant_tables_by_shop on public.restaurant_tables(shop_id,zone,label);
create index restaurant_menu_by_shop on public.restaurant_menu_items(shop_id,category);
create index salon_services_by_shop on public.salon_services(shop_id,active);
create index salon_requests_by_shop_date on public.salon_booking_requests(shop_id,requested_at);

-- All exposed data tables have RLS. Owners cannot access another shop even by forged IDs.
alter table public.restaurant_tables enable row level security;
alter table public.restaurant_menu_items enable row level security;
alter table public.salon_services enable row level security;
alter table public.salon_booking_links enable row level security;
alter table public.salon_booking_requests enable row level security;

-- No public table grants. Public catalogue / booking use narrowly scoped RPC below.
revoke all on public.restaurant_tables, public.restaurant_menu_items,
  public.salon_services, public.salon_booking_links,
  public.salon_booking_requests from anon, public;
grant select, insert, update on public.restaurant_tables, public.restaurant_menu_items,
  public.salon_services, public.salon_booking_links,
  public.salon_booking_requests to authenticated;

create policy restaurant_tables_owner on public.restaurant_tables
  for all to authenticated
  using (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='restaurant'))
  with check (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='restaurant'));
create policy restaurant_menu_owner on public.restaurant_menu_items
  for all to authenticated
  using (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='restaurant'))
  with check (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='restaurant'));
create policy salon_services_owner on public.salon_services
  for all to authenticated
  using (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='salon'))
  with check (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='salon'));
create policy salon_links_owner on public.salon_booking_links
  for all to authenticated
  using (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='salon'))
  with check (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='salon'));
create policy salon_requests_owner on public.salon_booking_requests
  for all to authenticated
  using (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='salon'))
  with check (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind='salon'));

-- Return only non-sensitive public salon information. No customer data is exposed.
create function public.get_public_salon_booking(p_token text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare out_data jsonb;
begin
  if p_token is null or length(p_token)<>64 then return null; end if;
  select jsonb_build_object(
    'shop_name', s.name,
    'services', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', sv.id, 'name', sv.name, 'price_xaf', sv.price_xaf,
        'duration_minutes', sv.duration_minutes
      ) order by sv.name)
      from public.salon_services sv where sv.shop_id=s.id and sv.active
    ), '[]'::jsonb)
  ) into out_data
  from public.salon_booking_links l
  join public.shops s on s.id=l.shop_id and s.business_kind='salon'
  where l.public_token=p_token and l.enabled;
  return out_data;
end;
$$;
revoke all on function public.get_public_salon_booking(text) from public, anon, authenticated;
grant execute on function public.get_public_salon_booking(text) to anon, authenticated;

-- Requests are unconfirmed until owner acceptance. No automatic appointment claim.
-- Anti-abuse: per-phone/day limit & near-identical duplicate rejection; production requires
-- additional edge/IP-based rate limit and CAPTCHA/Turnstile before enabling public access.
create function public.request_salon_booking(
  p_token text, p_first_name text, p_last_name text, p_phone text,
  p_requested_at timestamptz, p_service_id uuid default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_shop uuid; v_id uuid; v_phone text;
begin
  if length(coalesce(p_token,''))<>64 then raise exception 'Invalid booking link'; end if;
  select l.shop_id into v_shop
  from public.salon_booking_links l join public.shops s on s.id=l.shop_id
  where l.public_token=p_token and l.enabled and s.business_kind='salon';
  if v_shop is null then raise exception 'Booking link unavailable'; end if;
  if char_length(btrim(coalesce(p_first_name,''))) not between 1 and 80
     or char_length(btrim(coalesce(p_last_name,''))) not between 1 and 80
     or p_phone !~ '^\\+?[0-9][0-9 ()-]{5,23}$' then
    raise exception 'Invalid contact information';
  end if;
  if p_requested_at is null or p_requested_at <= now()
    or p_requested_at > now()+interval '180 days' then
    raise exception 'Invalid requested date';
  end if;
  if p_service_id is not null and not exists (
    select 1 from public.salon_services sv where sv.shop_id=v_shop and sv.id=p_service_id and sv.active
  ) then raise exception 'Service unavailable'; end if;
  v_phone:=regexp_replace(p_phone,'[^0-9+]','','g');
  perform pg_advisory_xact_lock(hashtext(v_shop::text || ':' || v_phone));
  if (select count(*) from public.salon_booking_requests r
      where r.shop_id=v_shop and r.phone=v_phone and r.created_at>now()-interval '24 hours')>=3 then
    raise exception 'Too many booking requests';
  end if;
  if exists(select 1 from public.salon_booking_requests r
    where r.shop_id=v_shop and r.phone=v_phone and r.requested_at=p_requested_at
      and r.status in ('pending','confirmed')) then
    raise exception 'This request already exists';
  end if;
  insert into public.salon_booking_requests(shop_id,service_id,first_name,last_name,phone,requested_at)
  values (v_shop,p_service_id,btrim(p_first_name),btrim(p_last_name),v_phone,p_requested_at)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.request_salon_booking(text,text,text,text,timestamptz,uuid) from public, anon, authenticated;
-- Deliberately hold public execute until CAPTCHA + edge rate limiting is integrated.
-- grant execute on function public.request_salon_booking(text,text,text,text,timestamptz,uuid) to anon;

comment on table public.salon_booking_requests is
 'Private unconfirmed customer requests; status pending is not a confirmed appointment.';
