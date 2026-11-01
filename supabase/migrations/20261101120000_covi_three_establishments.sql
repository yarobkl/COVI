-- Allow one owner account to manage up to three independent establishments.
drop index if exists public.shops_owner_id_uidx;

-- Enforce the quota for every onboarding RPC (including legacy/address-specific ones),
-- not only the generic creator. The transaction lock makes the check atomic.
create or replace function public.enforce_shop_owner_quota()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_count integer;
begin
  if auth.uid() is null or new.owner_id is distinct from auth.uid() then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));
  select count(*) into v_count from public.shops where owner_id = auth.uid();
  if v_count >= 3 then
    raise exception 'Shop quota reached';
  end if;
  return new;
end;
$function$;

drop trigger if exists shops_owner_quota on public.shops;
create trigger shops_owner_quota
before insert on public.shops
for each row execute function public.enforce_shop_owner_quota();

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

  -- Serialize creation attempts for the same owner so concurrent requests cannot
  -- both observe a count below three.
  perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text, 0));

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

-- Keep legacy four-argument clients safe: they now use the same quota-enforced path.
create or replace function public.create_my_shop(
  p_name text,
  p_city text default null,
  p_country text default 'Congo',
  p_currency text default 'XAF'
) returns public.shops
language sql
security invoker
set search_path = ''
as $function$
  select public.create_my_shop(p_name, p_city, p_country, p_currency, 'boutique');
$function$;

revoke all on function public.create_my_shop(text,text,text,text) from public, anon;
grant execute on function public.create_my_shop(text,text,text,text) to authenticated;
