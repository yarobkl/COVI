-- COVI SaaS multi-boutiques: quota enforced server-side.
-- IMPORTANT: apply ONLY after SaaS foundation, admin, and payment migrations,
-- after staging tests and explicit production authorization.
-- Legacy V1 users without a subscription may create ONE first shop.
-- No authenticated user can insert directly into shops.

-- Keep existing ownership-based read/update/delete policies, but remove INSERT.
drop policy if exists shops_owner_all on public.shops;
create policy shops_owner_read on public.shops for select to authenticated
  using (owner_id = (select auth.uid()));
create policy shops_owner_update on public.shops for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));
create policy shops_owner_delete on public.shops for delete to authenticated
  using (owner_id = (select auth.uid()));

-- Do not remove the unique index before the protected RPC exists.
create or replace function public.create_my_shop(
  p_name text,
  p_city text default null,
  p_country text default 'Congo',
  p_currency text default 'XAF'
) returns public.shops
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_shop public.shops;
  v_count integer;
  v_limit integer;
  v_account_id uuid;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if nullif(btrim(p_name), '') is null then
    raise exception 'Shop name is required' using errcode = '22023';
  end if;
  if p_currency is distinct from 'XAF' then
    raise exception 'Only XAF currency is supported' using errcode = '22023';
  end if;

  -- A single per-user advisory lock serializes concurrent shop creation
  -- even for legacy users who have no subscription row.
  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));

  select id into v_account_id from public.covi_owner_accounts
    where user_id = v_uid;

  if v_account_id is null then
    -- Existing V1 onboarding remains possible, but never a second shop.
    v_limit := 1;
  else
    select s.shop_limit into v_limit
      from public.covi_subscriptions s
      where s.owner_account_id = v_account_id
        and s.status = 'active'
        and s.period_start <= now()
        and s.period_end > now()
      for update;
    if not found then
      raise exception 'Active subscription required' using errcode = '42501';
    end if;
  end if;

  select count(*) into v_count from public.shops where owner_id = v_uid;
  if v_count >= v_limit then
    -- Compatibility: legacy V1 calls to create_my_shop return the
    -- existing shop when the single-shop limit is reached.
    if v_limit = 1 then
      select * into v_shop from public.shops
        where owner_id = v_uid order by created_at, id limit 1;
      return v_shop;
    end if;
    raise exception 'Shop quota reached' using errcode = 'P0001';
  end if;

  insert into public.shops(owner_id, name, city, country, currency)
    values (
      v_uid, btrim(p_name), nullif(btrim(p_city), ''),
      coalesce(nullif(btrim(p_country), ''), 'Congo'), 'XAF'
    )
    returning * into v_shop;
  return v_shop;
end;
$$;

revoke all on function public.create_my_shop(text,text,text,text) from public, anon;
grant execute on function public.create_my_shop(text,text,text,text) to authenticated;

-- Must drop only AFTER secure function and RLS policy are installed.
drop index if exists public.shops_owner_id_uidx;
create index if not exists shops_owner_id_lookup_idx on public.shops(owner_id);
