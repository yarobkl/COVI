-- COVI PME address V1: NEW establishments require a physical address in the new
-- signup RPC. Existing merchants and legacy RPCs are not changed or backfilled.
-- Apply only after full multi-sector migrations, never directly on live production.
alter table public.shops
  add column if not exists administrative_area text,
  add column if not exists address_line text;

alter table public.shops
  add constraint shops_administrative_area_length_check
    check (
      administrative_area is null
      or char_length(btrim(administrative_area)) between 2 and 120
    ),
  add constraint shops_address_line_length_check
    check (
      address_line is null
      or char_length(btrim(address_line)) between 10 and 240
    );

comment on column public.shops.administrative_area is
  'Arrondissement/commune/district of the establishment; entered during new PME signup.';
comment on column public.shops.address_line is
  'Required physical address for the new PME onboarding flow. NULL only for historical/legacy accounts.';

create function public.create_my_business_with_address(
  p_name text,
  p_city text,
  p_country text,
  p_administrative_area text,
  p_neighborhood text,
  p_address_line text,
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
  if nullif(btrim(p_city), '') is null or char_length(btrim(p_city)) > 120 then
    raise exception 'Valid city is required';
  end if;
  if p_country is null or p_country not in (
    'République du Congo', 'Cameroun', 'Gabon',
    'République centrafricaine', 'Guinée équatoriale', 'Tchad'
  ) then raise exception 'A supported CEMAC country is required'; end if;
  if p_administrative_area is null
     or char_length(btrim(p_administrative_area)) not between 2 and 120 then
    raise exception 'Arrondissement or commune is required';
  end if;
  if p_neighborhood is null or char_length(btrim(p_neighborhood)) not between 2 and 120 then
    raise exception 'Neighborhood is required';
  end if;
  if p_address_line is null or char_length(btrim(p_address_line)) not between 10 and 240 then
    raise exception 'Physical business address is required (10-240 characters)';
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
  ) then raise exception 'GPS coordinates or accuracy out of range'; end if;

  insert into public.shops (
    owner_id, name, city, country, administrative_area, neighborhood,
    address_line, currency, latitude, longitude, location_accuracy_m, business_kind
  ) values (
    auth.uid(), btrim(p_name), btrim(p_city), p_country, btrim(p_administrative_area),
    btrim(p_neighborhood), btrim(p_address_line), 'XAF', p_latitude, p_longitude,
    p_location_accuracy_m, p_business_kind
  ) returning * into v_shop;

  return v_shop;
end;
$$;

revoke all on function public.create_my_business_with_address(
  text,text,text,text,text,text,text,text,double precision,double precision,double precision
) from public, anon;
grant execute on function public.create_my_business_with_address(
  text,text,text,text,text,text,text,text,double precision,double precision,double precision
) to authenticated;
