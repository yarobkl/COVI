-- COVI multisector + private personnel foundation.
-- STAGED ONLY: do not apply to the live database without explicit approval.
-- Existing merchant workflows and historical rows remain retail by default.

alter table public.shops
  add column if not exists business_kind text not null default 'retail';

alter table public.shops
  add constraint shops_business_kind_check
  check (business_kind in ('retail', 'restaurant', 'salon'));

comment on column public.shops.business_kind is
  'retail=article/stock, restaurant=menu/orders, salon=services/appointments';

-- New RPC rather than replacing old location signup: protects older app versions.
create function public.create_my_business_with_location(
  p_name text,
  p_city text,
  p_country text,
  p_neighborhood text,
  p_business_kind text,
  p_currency text default 'XAF',
  p_latitude double precision default null,
  p_longitude double precision default null,
  p_location_accuracy_m double precision default null
)
returns public.shops
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_shop public.shops;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if nullif(btrim(p_name), '') is null then raise exception 'Business name is required'; end if;
  if nullif(btrim(p_city), '') is null or nullif(btrim(p_country), '') is null then
    raise exception 'Country and city are required';
  end if;
  if nullif(btrim(p_neighborhood), '') is null
     or char_length(btrim(p_neighborhood)) > 120 then
    raise exception 'Neighborhood is required and must be at most 120 characters';
  end if;
  if p_business_kind is null or p_business_kind not in ('retail', 'restaurant', 'salon') then
    raise exception 'Unsupported business kind';
  end if;
  if p_currency is distinct from 'XAF' then raise exception 'Only XAF is supported'; end if;
  if (p_latitude is null) is distinct from (p_longitude is null) then
    raise exception 'Latitude and longitude must be provided together';
  end if;
  if p_latitude is null and p_location_accuracy_m is not null then
    raise exception 'Accuracy requires GPS coordinates';
  end if;
  if p_latitude is not null and (
    p_latitude not between -90 and 90
    or p_longitude not between -180 and 180
    or (p_location_accuracy_m is not null
        and p_location_accuracy_m not between 0.1 and 100000)
  ) then
    raise exception 'GPS coordinates or accuracy out of range';
  end if;

  insert into public.shops(
    owner_id, name, city, country, neighborhood, currency,
    latitude, longitude, location_accuracy_m, business_kind
  )
  values (
    auth.uid(), btrim(p_name), btrim(p_city), btrim(p_country),
    btrim(p_neighborhood), 'XAF', p_latitude, p_longitude,
    p_location_accuracy_m, p_business_kind
  )
  returning * into v_shop;
  return v_shop;
end;
$$;

revoke all on function public.create_my_business_with_location(
  text,text,text,text,text,text,double precision,double precision,double precision
) from public, anon;
grant execute on function public.create_my_business_with_location(
  text,text,text,text,text,text,double precision,double precision,double precision
) to authenticated;

-- Staff identities are distinct from shop_members (app permissions and cashier PINs).
-- Employment records have NO login/authorization powers.
create table public.employees (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  full_name text not null check (char_length(btrim(full_name)) between 2 and 120),
  job_title text not null check (char_length(btrim(job_title)) between 2 and 100),
  compensation_mode text not null default 'fixed'
    check (compensation_mode in ('fixed', 'commission', 'mixed')),
  monthly_salary numeric(14,2) not null default 0 check (monthly_salary >= 0),
  commission_percent numeric(5,2) not null default 0
    check (commission_percent between 0 and 100),
  hired_on date,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint employees_mode_consistent check (
    compensation_mode = 'mixed'
    or (compensation_mode = 'fixed' and commission_percent = 0)
    or (compensation_mode = 'commission' and monthly_salary = 0)
  )
);
create index employees_shop_active_idx on public.employees(shop_id, active);

alter table public.employees enable row level security;
create policy employees_owner_select on public.employees for select to authenticated
  using (exists (
    select 1 from public.shops s
    where s.id = shop_id and s.owner_id = (select auth.uid())
  ));
create policy employees_owner_insert on public.employees for insert to authenticated
  with check (exists (
    select 1 from public.shops s
    where s.id = shop_id and s.owner_id = (select auth.uid())
  ));
create policy employees_owner_update on public.employees for update to authenticated
  using (exists (
    select 1 from public.shops s
    where s.id = shop_id and s.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.shops s
    where s.id = shop_id and s.owner_id = (select auth.uid())
  ));
-- Deliberately no DELETE policy: deactivate or archive; preserve salary history later.
grant select, insert, update on public.employees to authenticated;
revoke all on public.employees from anon;

comment on table public.employees is
  'Private employee directory and planned fixed compensation, NOT payroll or user access.';
