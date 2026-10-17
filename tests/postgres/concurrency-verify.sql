-- Runs in disposable covi_ci after both concurrent confirmations complete.
do $verify$
declare
  v_shop uuid := '11111111-1111-4111-8111-111111111111';
  v_orders uuid[] := array(
    select o.id from public.checkout_orders o
    where o.shop_id = v_shop
      and o.creation_operation_id in (
        '33330000-0000-4000-8000-000000000001'::uuid,
        '33330000-0000-4000-8000-000000000002'::uuid
      )
  );
  v_paid integer;
  v_approved integer;
  v_receipts integer;
  v_sales integer;
  v_movements integer;
  v_qty integer;
begin
  if cardinality(v_orders) <> 2 then
    raise exception 'Expected two independent orders, found %', cardinality(v_orders);
  end if;

  select count(*) into v_paid from public.checkout_orders o
  where o.id = any(v_orders) and o.status = 'paid';

  select count(*) into v_approved from public.checkout_orders o
  where o.id = any(v_orders) and o.status = 'approved';

  select count(*) into v_receipts from public.manual_payment_confirmations m
  where m.order_id = any(v_orders);

  select count(*) into v_sales from public.sales s
  where s.client_operation_id in (
    '44440000-0000-4000-8000-000000000001'::uuid,
    '44440000-0000-4000-8000-000000000002'::uuid
  );

  select count(*) into v_movements from public.stock_movements m
  where m.category_id = 'aaaaaaaa-0000-4000-8000-000000000009'
    and m.movement_type = 'sale';

  select quantity_on_hand into v_qty from public.stock_categories
  where id = 'aaaaaaaa-0000-4000-8000-000000000009';

  if v_paid <> 1 or v_approved <> 1 or v_receipts <> 1
     or v_sales <> 1 or v_movements <> 1 or v_qty <> 0 then
    raise exception 'Race guard failed: paid=% approved=% receipts=% sales=% moves=% stock=%',
      v_paid, v_approved, v_receipts, v_sales, v_movements, v_qty;
  end if;
end;
$verify$;

select 'PASS: Two simultaneous buyers of last garment → one paid sale, one rejected, stock zero' as result;
