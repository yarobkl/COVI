-- Optional GPS of the business; protected by existing owner-only shops RLS.
alter table public.shops
  add column if not exists latitude double precision,
  add column if not exists longitude double precision,
  add column if not exists location_accuracy_m double precision;

alter table public.shops add constraint shops_gps_position_valid
  check (
    (latitude is null and longitude is null and location_accuracy_m is null)
    or
    (
      latitude between -90 and 90 and longitude between -180 and 180
      and (location_accuracy_m is null or location_accuracy_m between 0.1 and 100000)
    )
  );

create or replace function public.create_my_shop_with_location(
  p_name text,
  p_city text,
  p_country text,
  p_neighborhood text,
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
declare v_shop public.shops;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if nullif(btrim(p_name), '') is null then raise exception 'Shop name is required'; end if;
  if nullif(btrim(p_city), '') is null or nullif(btrim(p_country), '') is null then
    raise exception 'Country and city are required';
  end if;
  if nullif(btrim(p_neighborhood), '') is null or
    char_length(btrim(p_neighborhood)) > 120 then
    raise exception 'Neighborhood is required and must be at most 120 characters';
  end if;
  if p_currency is distinct from 'XAF' then raise exception 'Only XAF is supported'; end if;
  if (p_latitude is null) is distinct from (p_longitude is null) then
    raise exception 'Latitude and longitude must be provided together';
  end if;
  if p_latitude is null and p_location_accuracy_m is not null then
    raise exception 'Accuracy requires GPS coordinates';
  end if;
  if p_latitude is not null and
     (p_latitude not between -90 and 90 or p_longitude not between -180 and 180
      or (p_location_accuracy_m is not null and p_location_accuracy_m not between 0.1 and 100000)) then
    raise exception 'GPS coordinates or accuracy out of range';
  end if;
  insert into public.shops(
    owner_id, name, city, country, neighborhood, currency,
    latitude, longitude, location_accuracy_m
  )
  values(
    auth.uid(), btrim(p_name), btrim(p_city), btrim(p_country),
    btrim(p_neighborhood), 'XAF',
    p_latitude, p_longitude, p_location_accuracy_m
  )
  returning * into v_shop;
  return v_shop;
end;
$$;
revoke all on function public.create_my_shop_with_location(
  text,text,text,text,text,double precision,double precision,double precision
) from public;
grant execute on function public.create_my_shop_with_location(
  text,text,text,text,text,double precision,double precision,double precision
) to authenticated;
