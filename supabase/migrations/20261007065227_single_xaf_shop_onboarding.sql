create unique index if not exists shops_owner_id_uidx on public.shops(owner_id);

alter table public.shops
  add constraint shops_currency_xaf_check check (currency = 'XAF');

create or replace function public.create_my_shop(
  p_name text,
  p_city text default null,
  p_country text default 'Congo',
  p_currency text default 'XAF'
)
returns public.shops
language plpgsql
set search_path to ''
as $function$
declare
  v_shop public.shops;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if nullif(trim(p_name), '') is null then
    raise exception 'Shop name is required';
  end if;

  insert into public.shops(owner_id, name, city, country, currency)
  values (
    auth.uid(),
    trim(p_name),
    nullif(trim(p_city), ''),
    coalesce(nullif(trim(p_country), ''), 'Congo'),
    'XAF'
  )
  on conflict (owner_id) do nothing
  returning * into v_shop;

  if not found then
    select * into v_shop from public.shops where owner_id = auth.uid();
  end if;
  return v_shop;
end;
$function$;
