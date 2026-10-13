-- Add a neighborhood to COVI shops without affecting existing shops or private sales.
alter table public.shops add column if not exists neighborhood text;

-- Historical shops can add their quartier later; new signup requires it.
alter table public.shops add constraint shops_neighborhood_length_check
  check (neighborhood is null or char_length(btrim(neighborhood)) between 1 and 120);

-- Keep create_my_shop for legacy mobile clients; the new signup uses the RPC below.
create or replace function public.create_my_shop_with_neighborhood(
  p_name text,
  p_city text,
  p_country text,
  p_neighborhood text,
  p_currency text default 'XAF'
)
returns public.shops
language plpgsql
security invoker
set search_path = ''
as $$
declare v_shop public.shops;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if nullif(btrim(p_name), '') is null then
    raise exception 'Shop name is required';
  end if;
  if nullif(btrim(p_city), '') is null or nullif(btrim(p_country), '') is null then
    raise exception 'Country and city are required';
  end if;
  if nullif(btrim(p_neighborhood), '') is null
    or char_length(btrim(p_neighborhood)) > 120 then
    raise exception 'Neighborhood is required and must be at most 120 characters';
  end if;
  if p_currency is distinct from 'XAF' then
    raise exception 'COVI currently only accepts XAF';
  end if;

  insert into public.shops(owner_id, name, city, country, neighborhood, currency)
    values (
      auth.uid(),
      btrim(p_name),
      btrim(p_city),
      btrim(p_country),
      btrim(p_neighborhood),
      'XAF'
    )
    returning * into v_shop;
  return v_shop;
end;
$$;

revoke all on function public.create_my_shop_with_neighborhood(text,text,text,text,text) from public;
grant execute on function public.create_my_shop_with_neighborhood(text,text,text,text,text)
  to authenticated;
