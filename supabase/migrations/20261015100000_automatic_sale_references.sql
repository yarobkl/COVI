-- Every recorded sale gets a unique, immutable COVI-generated operation reference.
-- Derived from the full UUID (not its truncated first 8 digits): no collision,
-- no mutable counter, and no operator-provided text.
-- Existing sales receive a reference automatically; no amount, stock, status or
-- payment verification field changes.
alter table public.sales
  add column operation_reference text generated always as
    ('COVI-' || pg_catalog.upper(pg_catalog.replace(id::text, '-', ''))) stored;

create unique index sales_operation_reference_uniq
  on public.sales (operation_reference);

-- RPC visibility only: never manufacture external Mobile Money / bank references.
-- Keep the existing PIN, stock, paid-verification and idempotence logic.
CREATE OR REPLACE FUNCTION public.list_public_orders(p_shop_id uuid, p_include_closed boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform public.assert_shop_owner(p_shop_id);
  return coalesce((
    select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', o.id, 'reference', o.reference, 'status', o.status, 'channel', o.channel,
      'createdAt', o.created_at, 'customerName', o.customer_name,
      'customerPhone', o.customer_phone, 'fulfillment', o.fulfillment,
      'deliveryAddress', o.delivery_address, 'paymentMethod', o.payment_method,
      'note', o.note, 'referenceImagePath', o.reference_image_path,
      'requestedTotalXaf', o.requested_total, 'saleId', o.sale_id, 'paidMethod', o.paid_method,
      'paymentReference', o.payment_reference,
      'internalReference', (select s.operation_reference from public.sales s where s.id = o.sale_id),
      'confirmedAt', o.confirmed_at,
      'cashierName', (select c.display_name from public.shop_cashier_profiles c
                      where c.id = o.cashier_profile_id),
      'rejectReason', o.reject_reason,
      'lines', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
          'id', l.id, 'productId', l.product_id, 'description', l.description,
          'productName', p.name, 'quantity', l.quantity,
          'listedUnitPriceXaf', l.listed_unit_price,
          'proposedUnitPriceXaf', l.proposed_unit_price,
          'currentPriceXaf', p.initial_sale_price,
          'availableQuantity', case when p.status = 'active' then p.quantity_on_hand else 0 end)
          order by l.position), '[]'::jsonb)
        from public.public_order_lines l left join public.products p on p.id = l.product_id
        where l.order_id = o.id))
      order by (o.status in ('new', 'accepted')) desc, o.created_at desc)
    from (
      select * from public.public_orders o
      where o.shop_id = p_shop_id
        and (p_include_closed or o.status in ('new', 'accepted')
             or o.updated_at > now() - interval '2 days')
      order by o.created_at desc
      limit 200
    ) o), '[]'::jsonb);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.get_public_order_status(p_tracking_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_order public.public_orders%rowtype;
  v_shop_name text;
  v_lines jsonb;
  v_receipt jsonb;
begin
  select * into v_order from public.public_orders o where o.tracking_token = p_tracking_token;
  if not found then return null; end if;
  select s.name into v_shop_name from public.shops s where s.id = v_order.shop_id;
  if v_order.status = 'paid' then
    select pg_catalog.jsonb_build_object(
      'receiptNumber', v.operation_reference,
      'internalReference', v.operation_reference,
      'confirmedAt', v_order.confirmed_at,
      'method', v_order.paid_method,
      'totalXaf', v.total_amount,
      'cashierName', (select c.display_name from public.shop_cashier_profiles c
                      where c.id = v_order.cashier_profile_id),
      'lines', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                  'label', p.name, 'quantity', i.quantity, 'unitPriceXaf', i.sold_unit_price)
                  order by p.name), '[]'::jsonb)
                from public.sale_items i join public.products p on p.id = i.product_id
                where i.sale_id = v.id))
      into v_receipt
    from public.sales v where v.id = v_order.sale_id;
  end if;
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'label', coalesce(p.name, l.description), 'quantity', l.quantity,
      'unitPriceXaf', coalesce(l.proposed_unit_price, l.listed_unit_price))
      order by l.position), '[]'::jsonb)
    into v_lines
  from public.public_order_lines l left join public.products p on p.id = l.product_id
  where l.order_id = v_order.id;
  return pg_catalog.jsonb_build_object(
    'shopName', v_shop_name, 'reference', v_order.reference, 'status', v_order.status,
    'createdAt', v_order.created_at, 'fulfillment', v_order.fulfillment,
    'paymentMethod', v_order.payment_method, 'amountXaf', v_order.requested_total,
    'lines', v_lines, 'rejectReason', v_order.reject_reason, 'receipt', v_receipt);
end;
$function$
;
CREATE OR REPLACE FUNCTION public.confirm_public_order_payment(p_order_id uuid, p_paid_method text, p_payment_reference text, p_payment_verified boolean, p_lines jsonb, p_till_session text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c_uuid_re constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_order public.public_orders%rowtype;
  v_ref text := nullif(pg_catalog.btrim(p_payment_reference), '');
  v_items jsonb := '[]'::jsonb;
  v_line public.public_order_lines%rowtype;
  v_item jsonb;
  v_product_id uuid;
  v_price numeric;
  v_sale_id uuid;
  v_sale public.sales%rowtype;
begin
  select * into v_order from public.public_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_order.shop_id);
  if v_order.status = 'paid' then
    return pg_catalog.jsonb_build_object('status', 'paid', 'saleId', v_order.sale_id,
      'alreadyConfirmed', true,
      'internalReference', (select s.operation_reference from public.sales s where s.id = v_order.sale_id));
  end if;
  if v_order.status not in ('new', 'accepted') then raise exception 'Order already closed'; end if;
  if p_payment_verified is not true then raise exception 'Payment not verified'; end if;
  if p_paid_method is null or p_paid_method not in ('cash', 'mobile_money', 'card', 'bank_transfer') then
    raise exception 'Invalid payment method';
  end if;
  if char_length(coalesce(v_ref, '')) > 64 or coalesce(v_ref ~ '[[:cntrl:]]', false) then
    raise exception 'Invalid payment reference';
  end if;
  if p_lines is null or pg_catalog.jsonb_typeof(p_lines) <> 'array'
     or pg_catalog.jsonb_array_length(p_lines)
        <> (select count(*) from public.public_order_lines l where l.order_id = v_order.id) then
    raise exception 'Every order line must be confirmed';
  end if;

  for v_line in select * from public.public_order_lines l where l.order_id = v_order.id
                order by l.position loop
    select e.value into v_item from pg_catalog.jsonb_array_elements(p_lines) e
    where e.value ->> 'lineId' = v_line.id::text;
    if v_item is null
       or (v_item ->> 'productId') is null or (v_item ->> 'productId') !~ c_uuid_re
       or pg_catalog.jsonb_typeof(v_item -> 'unitPriceXaf') is distinct from 'number' then
      raise exception 'Every order line must be confirmed';
    end if;
    v_product_id := (v_item ->> 'productId')::uuid;
    v_price := (v_item ->> 'unitPriceXaf')::numeric;
    if v_line.product_id is not null and v_line.product_id <> v_product_id then
      raise exception 'Order line product mismatch';
    end if;
    if not exists (select 1 from public.products p
                   where p.id = v_product_id and p.shop_id = v_order.shop_id) then
      raise exception 'Product unavailable';
    end if;
    v_items := v_items || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
      'product_id', v_product_id, 'quantity', v_line.quantity, 'sold_unit_price', v_price));
  end loop;

  v_sale_id := public.record_cart_sale(v_order.shop_id, v_items, p_paid_method, v_order.id,
                                       p_till_session);
  select * into v_sale from public.sales where id = v_sale_id;

  update public.public_orders
  set status = 'paid', sale_id = v_sale_id, paid_method = p_paid_method,
      payment_reference = v_ref, confirmed_at = now(), confirmed_by = auth.uid(),
      cashier_profile_id = v_sale.cashier_profile_id,
      decided_at = coalesce(decided_at, now())
  where id = v_order.id;
  update public.public_order_lines l set product_id = (e.value ->> 'productId')::uuid
  from pg_catalog.jsonb_array_elements(p_lines) e
  where l.order_id = v_order.id and e.value ->> 'lineId' = l.id::text and l.product_id is null;

  perform public.shop_audit(v_order.shop_id, 'public_order_paid', v_order.id::text,
    pg_catalog.jsonb_build_object('sale_id', v_sale_id, 'method', p_paid_method));
  return pg_catalog.jsonb_build_object('status', 'paid', 'saleId', v_sale_id,
    'alreadyConfirmed', false,
    'internalReference', v_sale.operation_reference);
end;
$function$
;
