-- COVI V1: DRAFT, OWNER-ONLY manual order intake and approval.
-- DO NOT APPLY TO PRODUCTION. Requires draft_category_stock_schema.sql
-- and draft_checkout_manual_payment_schema.sql first.
-- No payment is captured, no stock is decremented, and no employees or
-- anonymous visitors are authorized by these two functions.
begin;

create or replace function public.create_manual_checkout_order(
  p_shop_id uuid,
  p_operation_id uuid,
  p_lines jsonb,
  p_is_test boolean default false,
  p_customer_phone text default null,
  p_customer_note text default null,
  p_fulfillment text default 'pickup'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_canonical jsonb;
  v_payload jsonb;
  v_total numeric;
  v_order public.checkout_orders%rowtype;
  v_line record;
  v_phone text := nullif(btrim(p_customer_phone), '');
  v_note text := nullif(btrim(p_customer_note), '');
begin
  if v_actor is null then
    raise exception 'Authentification requise' using errcode = '28000';
  end if;
  if p_shop_id is null or p_operation_id is null then
    raise exception 'Identifiants de commande manquants';
  end if;
  if not exists (
    select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_actor
  ) then
    raise exception 'Accès à cette boutique refusé' using errcode = '42501';
  end if;
  if p_is_test is null or p_fulfillment not in ('pickup', 'delivery') or p_fulfillment is null then
    raise exception 'Paramètres de commande invalides';
  end if;
  if char_length(v_phone) > 32 or char_length(v_note) > 500
     or coalesce(v_phone ~ '[[:cntrl:]]', false)
     or coalesce(v_note ~ '[[:cntrl:]]', false) then
    raise exception 'Coordonnées ou notes invalides';
  end if;

  if jsonb_typeof(p_lines) is distinct from 'array' then
    raise exception 'Le panier doit être une liste';
  end if;
  if jsonb_array_length(p_lines) < 1 or jsonb_array_length(p_lines) > 100 then
    raise exception 'La commande exige entre 1 et 100 lignes';
  end if;

  -- All casts happen AFTER checking types and ranges (untrusted client JSON).
  if exists (
    select 1 from jsonb_array_elements(p_lines) as e(item)
    where jsonb_typeof(e.item) is distinct from 'object'
       or jsonb_typeof(e.item->'categoryId') is distinct from 'string'
       or (e.item->>'categoryId') !~*
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
       or jsonb_typeof(e.item->'quantity') is distinct from 'number'
       or coalesce((e.item->>'quantity') !~ '^[1-9][0-9]{0,9}$', true)
       or jsonb_typeof(e.item->'unitPriceXaf') is distinct from 'number'
       or coalesce((e.item->>'unitPriceXaf') !~ '^(0|[1-9][0-9]{0,12})$', true)
  ) then
    raise exception 'Catégorie, quantité ou prix invalide';
  end if;
  if exists (
    select 1 from jsonb_array_elements(p_lines) as e(item)
    where (e.item->>'quantity')::bigint > 2147483647
       or (e.item->>'unitPriceXaf')::numeric > 9000000000000
  ) then
    raise exception 'Quantité ou prix hors limite';
  end if;

  -- Group identical category/negotiated-price pairs to make retries independent
  -- of row order, while keeping different negotiated prices distinct.
  select jsonb_agg(jsonb_build_object(
      'categoryId', t.category_id,
      'quantity', t.quantity,
      'unitPriceXaf', t.unit_price
    ) order by t.category_id, t.unit_price),
    coalesce(sum(t.quantity::numeric * t.unit_price), 0)
  into v_canonical, v_total
  from (
    select (e.item->>'categoryId')::uuid as category_id,
           sum((e.item->>'quantity')::bigint) as quantity,
           (e.item->>'unitPriceXaf')::numeric as unit_price
    from jsonb_array_elements(p_lines) as e(item)
    group by (e.item->>'categoryId')::uuid, (e.item->>'unitPriceXaf')::numeric
  ) as t;

  if v_total > 9000000000000 then
    raise exception 'Total de commande trop élevé';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_canonical) as e(item)
    where (e.item->>'quantity')::bigint > 2147483647
       or (e.item->>'quantity')::numeric * (e.item->>'unitPriceXaf')::numeric > 9000000000000
  ) then
    raise exception 'Ligne de commande hors limite';
  end if;
  if exists (
    select 1 from jsonb_array_elements(v_canonical) as e(item)
    left join public.stock_categories c
      on c.id = (e.item->>'categoryId')::uuid and c.shop_id = p_shop_id
       and c.is_test = p_is_test
    where c.id is null
  ) then
    raise exception 'Une catégorie ne fait pas partie du stock de cette boutique';
  end if;
  -- Even at multiple negotiated prices, a category cannot exceed an int4 count.
  if exists (
    select 1 from (
      select sum((e.item->>'quantity')::bigint) as category_quantity
      from jsonb_array_elements(v_canonical) as e(item)
      group by (e.item->>'categoryId')::uuid
    ) as quantities
    where quantities.category_quantity > 2147483647
  ) then
    raise exception 'Quantité totale de catégorie hors limite';
  end if;

  v_payload := jsonb_build_object(
    'channel', 'manual',
    'lines', v_canonical,
    'isTest', p_is_test,
    'customerPhone', v_phone,
    'customerNote', v_note,
    'fulfillment', p_fulfillment
  );

  -- Serialize retries by operation UUID even before the first row exists.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'covi:manual-order:' || p_shop_id::text || ':' || p_operation_id::text, 0
    )
  );
  select * into v_order from public.checkout_orders o
    where o.shop_id = p_shop_id and o.creation_operation_id = p_operation_id;
  if found then
    if v_order.created_by = v_actor and v_order.creation_payload = v_payload then
      return jsonb_build_object(
        'orderId', v_order.id,
        'status', v_order.status,
        'amountXaf', v_order.amount_xaf
      );
    end if;
    raise exception 'Identifiant de commande déjà utilisé avec un panier différent';
  end if;

  insert into public.checkout_orders (
    shop_id, channel, status, is_test, customer_phone, customer_note,
    fulfillment, amount_xaf, creation_operation_id, creation_payload, created_by
  ) values (
    p_shop_id, 'manual', 'submitted', p_is_test, v_phone, v_note,
    p_fulfillment, v_total::bigint, p_operation_id, v_payload, v_actor
  ) returning * into v_order;

  for v_line in
    select (e.item->>'categoryId')::uuid as category_id,
           (e.item->>'quantity')::integer as quantity,
           (e.item->>'unitPriceXaf')::bigint as unit_price
    from jsonb_array_elements(v_canonical) as e(item)
  loop
    insert into public.checkout_order_lines (
      shop_id, order_id, category_id, quantity, negotiated_unit_price_xaf
    ) values (
      p_shop_id, v_order.id, v_line.category_id, v_line.quantity, v_line.unit_price
    );
  end loop;

  return jsonb_build_object(
    'orderId', v_order.id, 'status', v_order.status, 'amountXaf', v_order.amount_xaf
  );
end;
$function$;

create or replace function public.approve_manual_checkout_order(
  p_shop_id uuid,
  p_order_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_order public.checkout_orders%rowtype;
  v_count integer;
  v_total numeric;
  v_category record;
  v_stock record;
begin
  if v_actor is null then
    raise exception 'Authentification requise' using errcode = '28000';
  end if;
  if p_shop_id is null or p_order_id is null then
    raise exception 'Identifiants de commande manquants';
  end if;
  if not exists (
    select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_actor
  ) then
    raise exception 'Accès à cette boutique refusé' using errcode = '42501';
  end if;

  select * into v_order
  from public.checkout_orders o
  where o.id = p_order_id and o.shop_id = p_shop_id
  for update;
  if not found then raise exception 'Commande introuvable'; end if;

  -- Only manually created orders are approved by this owner-only entry point.
  -- Future QR and social orders need their own audited public intake.
  if v_order.channel <> 'manual' then
    raise exception 'Ce canal de commande ne peut pas être approuvé ici';
  end if;
  if v_order.status = 'approved' then
    return jsonb_build_object('orderId', v_order.id, 'status', 'approved',
                              'amountXaf', v_order.amount_xaf);
  end if;
  if v_order.status <> 'submitted' then
    raise exception 'La commande ne peut plus être approuvée';
  end if;

  select count(*)::integer, coalesce(sum(l.line_total_xaf), 0)
    into v_count, v_total
  from public.checkout_order_lines l
  where l.order_id = p_order_id and l.shop_id = p_shop_id;
  if v_count < 1 or v_count > 100
     or v_total <> v_order.amount_xaf or v_total > 9000000000000 then
    raise exception 'Le montant des lignes ne correspond pas à la commande';
  end if;

  -- Approval checks availability but DOES NOT reserve inventory or decrement it.
  -- If other sales happen first, payment confirmation may later reject this order.
  for v_category in
    select l.category_id, sum(l.quantity)::bigint as quantity
    from public.checkout_order_lines l
    join public.stock_categories c
      on c.id = l.category_id and c.shop_id = l.shop_id
    where l.shop_id = p_shop_id and l.order_id = p_order_id
    group by l.category_id, c.category_key
    order by c.category_key, l.category_id
  loop
    if v_category.quantity < 1 or v_category.quantity > 2147483647 then
      raise exception 'Quantité de catégorie invalide';
    end if;
    select c.quantity_on_hand, c.quantity_reserved, c.is_test
      into v_stock
      from public.stock_categories c
      where c.id = v_category.category_id and c.shop_id = p_shop_id
      for update;
    if not found or v_stock.is_test is distinct from v_order.is_test
       or v_stock.quantity_on_hand - v_stock.quantity_reserved < v_category.quantity then
      raise exception 'Stock disponible insuffisant ou catégorie incorrecte';
    end if;
  end loop;

  update public.checkout_orders
  set status = 'approved', approved_by = v_actor, approved_at = now(),
      updated_at = now()
  where id = p_order_id and shop_id = p_shop_id and status = 'submitted';

  return jsonb_build_object(
    'orderId', v_order.id, 'status', 'approved', 'amountXaf', v_order.amount_xaf
  );
end;
$function$;

revoke all on function public.create_manual_checkout_order(
  uuid, uuid, jsonb, boolean, text, text, text
) from public, anon;
grant execute on function public.create_manual_checkout_order(
  uuid, uuid, jsonb, boolean, text, text, text
) to authenticated;

revoke all on function public.approve_manual_checkout_order(uuid, uuid)
  from public, anon;
grant execute on function public.approve_manual_checkout_order(uuid, uuid)
  to authenticated;

commit;

-- RELEASE GATES: run on a disposable Supabase branch or local Postgres DB.
-- Test another shop, null JWT, mutated payload retry, concurrent creation,
-- test stock vs real stock, overselling, decimal/noninteger input, and rollbacks.
-- Verify SECURITY DEFINER function owner and function EXECUTE privileges.
-- This design is OWNER ONLY: typed first name does not authorize employees.
