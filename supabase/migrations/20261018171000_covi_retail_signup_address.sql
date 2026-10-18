-- Additive production-safe first stage for COVI PME registration.
-- Legacy XAF shops, their functions and financial records are untouched.
alter table public.shops
  add column if not exists administrative_area text,
  add column if not exists address_line text;

comment on column public.shops.administrative_area is
  'Optional for legacy shops, required for new retail registration.';
comment on column public.shops.address_line is
  'Optional for legacy shops, required for new retail registration.';

create or replace function public.create_my_retail_shop_with_address(
  p_name text,
  p_city text,
  p_country text,
  p_administrative_area text,
  p_neighborhood text,
  p_address_line text,
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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 120 then
    raise exception 'Business name is required (2-120 characters)';
  end if;
  if p_city is null or char_length(btrim(p_city)) not between 2 and 120 then
    raise exception 'City is required (2-120 characters)';
  end if;
  if p_country is null or p_country not in (
    'République du Congo', 'Cameroun', 'Gabon', 'Tchad',
    'République centrafricaine', 'Guinée équatoriale'
  ) then
    raise exception 'Retail cash register currently supports CEMAC countries only';
  end if;
  if p_currency is distinct from 'XAF' then
    raise exception 'Only XAF is supported by the current cash register';
  end if;
  if p_administrative_area is null or
     char_length(btrim(p_administrative_area)) not between 2 and 120 then
    raise exception 'Administrative area is required';
  end if;
  if p_neighborhood is null or
     char_length(btrim(p_neighborhood)) not between 2 and 120 then
    raise exception 'Neighborhood is required';
  end if;
  if p_address_line is null or
     char_length(btrim(p_address_line)) not between 10 and 240 or
     btrim(p_address_line) !~ '[[:space:]]' then
    raise exception 'A descriptive physical business address is required';
  end if;
  if (p_latitude is null) is distinct from (p_longitude is null) then
    raise exception 'Latitude and longitude must be provided together';
  end if;
  if p_latitude is null and p_location_accuracy_m is not null then
    raise exception 'Accuracy requires GPS coordinates';
  end if;
  if p_latitude is not null and (
    p_latitude not between -90 and 90 or
    p_longitude not between -180 and 180 or
    (p_location_accuracy_m is not null and
     p_location_accuracy_m not between 0.1 and 100000)
  ) then
    raise exception 'GPS coordinates or accuracy out of range';
  end if;

  -- SECURITY INVOKER: shops RLS ties owner_id to auth.uid().
  insert into public.shops(
    owner_id, name, city, country, administrative_area, neighborhood,
    address_line, currency, latitude, longitude, location_accuracy_m
  )
  values (
    auth.uid(), btrim(p_name), btrim(p_city), p_country,
    btrim(p_administrative_area), btrim(p_neighborhood),
    btrim(p_address_line), 'XAF', p_latitude, p_longitude,
    p_location_accuracy_m
  )
  returning * into v_shop;
  return v_shop;
end;
$$;
revoke all on function public.create_my_retail_shop_with_address(
  text,text,text,text,text,text,text,double precision,double precision,double precision
) from public, anon;
grant execute on function public.create_my_retail_shop_with_address(
  text,text,text,text,text,text,text,double precision,double precision,double precision
) to authenticated;