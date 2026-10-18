-- Country-aware business registration currency, following address-onboarding migration.
-- Safe for historical shops: add nullable secondary currency and preserve their base currency.
-- NOTE: This only establishes tenant currency metadata; no FX conversion or payment engine
-- enablement is implied by this migration. Do not activate non-XAF flows in prod until audited.
alter table public.shops
  add column if not exists secondary_currency text;

alter table public.shops
  add constraint shops_secondary_currency_scope_check
  check (
    secondary_currency is null
    or (country = 'République démocratique du Congo' and currency = 'CDF'
        and secondary_currency = 'USD')
  );

comment on column public.shops.secondary_currency is
  'Informational supported settlement currency for future verified FX logic (DRC USD); NOT a second accounting ledger.';

create or replace function public.create_my_business_with_address(
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
    'République du Congo','Cameroun','Gabon','République centrafricaine','Guinée équatoriale','Tchad',
    'Côte d’Ivoire','Bénin','Sénégal','Togo','Guinée-Bissau','Burkina Faso','Mali','Niger',
    'Ghana','Nigeria','Guinée','Gambie','Libéria','Sierra Leone','Cap-Vert',
    'République démocratique du Congo','Angola','São Tomé-et-Príncipe','Burundi','Rwanda'
  ) then raise exception 'Unsupported African market country'; end if;
  if p_administrative_area is null
     or char_length(btrim(p_administrative_area)) not between 2 and 120 then
    raise exception 'Arrondissement or commune is required';
  end if;
  if p_neighborhood is null or char_length(btrim(p_neighborhood)) not between 2 and 120 then
    raise exception 'Neighborhood is required';
  end if;
  if p_address_line is null or char_length(btrim(p_address_line)) not between 10 and 240
     or btrim(p_address_line) !~ '[[:space:]]' then
    raise exception 'Physical business address is required (10-240 characters)';
  end if;
  if p_business_kind is null or p_business_kind not in ('retail', 'restaurant', 'salon') then
    raise exception 'Unsupported business kind';
  end if;
  -- The country's official accounting currency must match exactly. XAF and XOF
  -- are independent legal currencies; never infer 1:1 conversion from face value.
  if p_currency is distinct from (case
    when p_country in (
      'République du Congo','Cameroun','Gabon','République centrafricaine',
      'Guinée équatoriale','Tchad'
    ) then 'XAF'
    when p_country in (
      'Côte d’Ivoire','Bénin','Sénégal','Togo','Guinée-Bissau',
      'Burkina Faso','Mali','Niger'
    ) then 'XOF'
    when p_country = 'Ghana' then 'GHS'
    when p_country = 'Nigeria' then 'NGN'
    when p_country = 'Guinée' then 'GNF'
    when p_country = 'Gambie' then 'GMD'
    when p_country = 'Libéria' then 'LRD'
    when p_country = 'Sierra Leone' then 'SLE'
    when p_country = 'Cap-Vert' then 'CVE'
    when p_country = 'République démocratique du Congo' then 'CDF'
    when p_country = 'Angola' then 'AOA'
    when p_country = 'São Tomé-et-Príncipe' then 'STN'
    when p_country = 'Burundi' then 'BIF'
    when p_country = 'Rwanda' then 'RWF'
    else null end)
  then raise exception 'Currency is not valid for the selected country'; end if;
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
    address_line, currency, secondary_currency, latitude, longitude,
    location_accuracy_m, business_kind
  ) values (
    auth.uid(), btrim(p_name), btrim(p_city), p_country, btrim(p_administrative_area),
    btrim(p_neighborhood), btrim(p_address_line), p_currency,
    case when p_country = 'République démocratique du Congo' then 'USD' else null end,
    p_latitude, p_longitude, p_location_accuracy_m, p_business_kind
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
