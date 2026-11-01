-- Allow one owner account to manage up to three independent establishments.
drop index if exists public.shops_owner_id_uidx;

create or replace function public.create_my_shop(
  p_name text,
  p_city text default null,
  p_country text default 'Congo',
  p_currency text default 'XAF',
  p_business_kind text default 'boutique'
) returns public.shops
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_shop public.shops;
  v_count integer;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if nullif(trim(p_name), '') is null then
    raise exception 'Shop name is required';
  end if;
  if coalesce(trim(p_business_kind), '') not in ('boutique', 'restaurant', 'salon') then
    raise exception 'Unsupported business kind';
  end if;

  select count(*) into v_count
  from public.shops
  where owner_id = auth.uid();

  if v_count >= 3 then
    raise exception 'Shop quota reached';
  end if;

  insert into public.shops(owner_id, name, city, country, currency, business_kind)
  values (
    auth.uid(),
    trim(p_name),
    nullif(trim(p_city), ''),
    coalesce(nullif(trim(p_country), ''), 'Congo'),
    coalesce(nullif(trim(p_currency), ''), 'XAF'),
    trim(p_business_kind)
  )
  returning * into v_shop;

  return v_shop;
end;
$function$;

grant execute on function public.create_my_shop(text,text,text,text,text) to authenticated;
