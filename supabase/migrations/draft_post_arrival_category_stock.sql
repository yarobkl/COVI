-- DRAFT ONLY — DO NOT RUN AGAINST PRODUCTION.
-- Requires draft_category_stock_schema.sql. Review on an isolated database.
-- Receives categories for an existing received arrival (ballon or supplier order).
-- One arrival can be posted only once; existing historical arrivals are NOT imported.
begin;

create or replace function public.post_arrival_category_stock(
  p_shop_id uuid,
  p_arrival_id uuid,
  p_operation_id uuid,
  p_lines jsonb
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid;
  v_arrival record;
  v_count integer;
  v_row record;
  v_category_id uuid;
  v_existing integer;
  v_total integer := 0;
begin
  v_owner := (select auth.uid());
  if v_owner is null then raise exception 'Authentication required'; end if;
  if p_shop_id is null or p_arrival_id is null or p_operation_id is null then
    raise exception 'Missing identifiers';
  end if;
  if not exists (select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_owner) then
    raise exception 'Shop access denied';
  end if;

  -- Serialize retries and concurrent requests for this arrival.
  select a.id, a.status, a.is_test
    into v_arrival
    from public.arrivals a
    where a.id = p_arrival_id and a.shop_id = p_shop_id
    for update;
  if not found then raise exception 'Arrival not found'; end if;
  if v_arrival.status <> 'received' then raise exception 'Arrival is not received'; end if;

  select count(*)::integer into v_existing
    from public.arrival_category_items ai
    where ai.arrival_id = p_arrival_id and ai.shop_id = p_shop_id;
  if v_existing > 0 then
    -- Idempotent only for the same operation ID; mismatched retry is a conflict.
    if exists (
      select 1 from public.stock_movements m
      where m.shop_id = p_shop_id and m.arrival_id = p_arrival_id
        and m.operation_id <> p_operation_id
    ) then raise exception 'Arrival already posted with another operation'; end if;
    if exists (
      select 1 from public.stock_movements m
      where m.shop_id = p_shop_id and m.arrival_id = p_arrival_id
        and m.operation_id = p_operation_id
    ) then return 0; end if;
    raise exception 'Arrival has inconsistent existing posting';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) not between 1 and 100 then
    raise exception 'Invalid reception lines';
  end if;
  -- Duplicate category keys are aggregated; the JSON schema is strictly checked.
  if exists (
    select 1 from jsonb_array_elements(p_lines) x
    where jsonb_typeof(x) <> 'object'
       or jsonb_typeof(x->'categoryKey') is distinct from 'string'
       or jsonb_typeof(x->'quantity') is distinct from 'number'
       or (x->>'quantity') !~ '^[0-9]{1,10}$'
       or length(x->>'categoryKey') > 80
       or (x->>'categoryKey') !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
  ) then raise exception 'Invalid category or quantity'; end if;

  for v_row in
    select x->>'categoryKey' as category_key,
           sum((x->>'quantity')::bigint) as qty
    from jsonb_array_elements(p_lines) x
    group by x->>'categoryKey'
    order by x->>'categoryKey'
  loop
    if v_row.qty <= 0 or v_row.qty > 2147483647 then
      raise exception 'Invalid quantity';
    end if;

    insert into public.stock_categories
      (shop_id, category_key, display_name, quantity_on_hand, is_test)
    values (p_shop_id, v_row.category_key, v_row.category_key, 0, v_arrival.is_test)
    on conflict (shop_id, category_key, is_test) do nothing;

    select c.id into v_category_id
      from public.stock_categories c
      where c.shop_id = p_shop_id
        and c.category_key = v_row.category_key
        and c.is_test = v_arrival.is_test
      for update;

    update public.stock_categories
       set quantity_on_hand = quantity_on_hand + v_row.qty::integer,
           updated_at = now()
     where id = v_category_id
       and quantity_on_hand <= 2147483647 - v_row.qty;

    if not found then raise exception 'Stock quantity overflow'; end if;

    insert into public.arrival_category_items
      (shop_id, arrival_id, category_id, quantity_received)
    values (p_shop_id, p_arrival_id, v_category_id, v_row.qty::integer);

    insert into public.stock_movements
      (shop_id, category_id, movement_type, quantity_delta, arrival_id, operation_id)
    values (p_shop_id, v_category_id, 'receipt', v_row.qty::integer,
            p_arrival_id, p_operation_id);

    v_total := v_total + 1;
  end loop;
  return v_total;
end;
$$;

-- SECURITY DEFINER must never be callable by anonymous/public roles.
revoke all on function public.post_arrival_category_stock(uuid, uuid, uuid, jsonb) from public, anon;
grant execute on function public.post_arrival_category_stock(uuid, uuid, uuid, jsonb) to authenticated;
commit;

-- Pre-release review:
-- 1. SECURITY DEFINER owner should be a narrowly privileged role, not a general admin.
-- 2. Confirm owner bypass behavior and all grants on the three new tables.
-- 3. Test retries with altered payloads; current implementation checks operation ID,
--    but does NOT compare payload hashes and therefore must be strengthened before release.
-- 4. Test malformed numeric JSON and integer overflows in a disposable database.
-- 5. Validate RLS and concurrent arrivals from different shops.
