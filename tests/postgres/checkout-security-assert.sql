-- Negative transaction/authorization checks in disposable covi_ci only.
-- Applies after the basic and concurrent checkout scenarios.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

do $negative$
declare
  v_shop uuid := '11111111-1111-4111-8111-111111111111';
  v_multi uuid;
  v_competing uuid;
  v_test_order uuid;
  v_count_before integer;
  v_counter_before bigint;
  v_stock_chemises integer;
  v_stock_real_robes integer;
  v_rejected boolean;
  v_result jsonb;
begin
  -- A two-category order is approved while everything is available.
  v_multi := (
    public.create_manual_checkout_order(
      v_shop,
      '55550000-0000-4000-8000-000000000001',
      '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000001","quantity":3,"unitPriceXaf":4000},
        {"categoryId":"aaaaaaaa-0000-4000-8000-000000000002","quantity":1,"unitPriceXaf":2500}]'::jsonb
    )->>'orderId'
  )::uuid;
  perform public.approve_manual_checkout_order(v_shop, v_multi);

  -- Another real order legitimately consumes one robe first.
  v_competing := (
    public.create_manual_checkout_order(
      v_shop,
      '55550000-0000-4000-8000-000000000002',
      '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000001","quantity":1,"unitPriceXaf":3000}]'::jsonb
    )->>'orderId'
  )::uuid;
  perform public.approve_manual_checkout_order(v_shop, v_competing);
  perform public.confirm_manual_checkout_payment(
    v_shop, v_competing, '66660000-0000-4000-8000-000000000002',
    'Fatou', 'cash', null
  );

  select count(*) into v_count_before from public.manual_payment_confirmations
    where shop_id=v_shop;
  select coalesce(max(last_number),0) into v_counter_before
    from public.shop_receipt_counters
    where shop_id=v_shop and is_test=false;
  select quantity_on_hand into v_stock_chemises
    from public.stock_categories
    where id='aaaaaaaa-0000-4000-8000-000000000002';

  -- The previously approved multi-category sale is no longer payable.
  -- Failure must not consume a receipt counter, sale row or stock.
  v_rejected := false;
  begin
    perform public.confirm_manual_checkout_payment(
      v_shop, v_multi, '66660000-0000-4000-8000-000000000001',
      'Marie Lou', 'mobile_money', null
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'Oversell was accepted after approval became stale';
  end if;
  if (select status from public.checkout_orders where id=v_multi)<>'approved' then
    raise exception 'Failed payment modified order status';
  end if;
  if (select count(*) from public.manual_payment_confirmations
      where shop_id=v_shop)<>v_count_before then
    raise exception 'Failed payment inserted a receipt';
  end if;
  if (select quantity_on_hand from public.stock_categories
      where id='aaaaaaaa-0000-4000-8000-000000000002')<>v_stock_chemises then
    raise exception 'Failed multi-category payment consumed chemises';
  end if;
  if (select count(*) from public.sales
      where client_operation_id='66660000-0000-4000-8000-000000000001')<>0 then
    raise exception 'Failed payment inserted a sales ledger entry';
  end if;
  if (select count(*) from public.stock_movements
      where operation_id='66660000-0000-4000-8000-000000000001')<>0 then
    raise exception 'Failed payment inserted a stock movement';
  end if;
  if (select coalesce(max(last_number),0) from public.shop_receipt_counters
      where shop_id=v_shop and is_test=false)<>v_counter_before then
    raise exception 'Failed payment consumed a receipt counter';
  end if;

  select quantity_on_hand into v_stock_real_robes
    from public.stock_categories
    where id='aaaaaaaa-0000-4000-8000-000000000001';

  -- TEST order uses a distinct stock row and visibly separate receipt prefix.
  v_test_order := (
    public.create_manual_checkout_order(
      v_shop,
      '55550000-0000-4000-8000-000000000003',
      '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1,"unitPriceXaf":2000}]'::jsonb,
      true
    )->>'orderId'
  )::uuid;
  perform public.approve_manual_checkout_order(v_shop, v_test_order);
  v_result := public.confirm_manual_checkout_payment(
    v_shop, v_test_order, '66660000-0000-4000-8000-000000000003',
    'Oumar', 'cash', null
  );
  if (v_result->>'receiptNumber') not like 'CV-TEST-%' then
    raise exception 'TEST receipt missing its prefix: %', v_result;
  end if;
  if (select is_test from public.sales
      where id=(v_result->>'saleId')::uuid) is distinct from true then
    raise exception 'TEST sale leaked into real sales ledger';
  end if;
  if (select quantity_on_hand from public.stock_categories
      where id='aaaaaaaa-0000-4000-8000-000000000001')<>v_stock_real_robes then
    raise exception 'TEST sale changed real stock';
  end if;
  if (select quantity_on_hand from public.stock_categories
      where id='aaaaaaaa-0000-4000-8000-000000000003')<>1 then
    raise exception 'TEST sale did not decrement TEST stock by one';
  end if;
end;
$negative$;
commit;

-- Save the target order id before entering shop B's RLS context.
-- Shop B cannot SELECT A's orders, as intended.
select set_config('covi.test.target_order', (
  select id::text from public.checkout_orders
   where creation_operation_id='55550000-0000-4000-8000-000000000001'
), false);

-- A different authenticated shop owner may not approve or confirm shop A's order.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', true);
do $cross_shop$
declare
  v_shop uuid := '11111111-1111-4111-8111-111111111111';
  v_order uuid;
  v_rejected boolean;
begin
  v_order := current_setting('covi.test.target_order')::uuid;
  v_rejected := false;
  begin
    perform public.approve_manual_checkout_order(v_shop, v_order);
  exception when insufficient_privilege then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Other shop owner approved order'; end if;

  v_rejected := false;
  begin
    perform public.confirm_manual_checkout_payment(
      v_shop, v_order, '66660000-0000-4000-8000-000000000099',
      'Fake Cashier', 'cash', null
    );
  exception when insufficient_privilege then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Other shop owner confirmed payment'; end if;
end;
$cross_shop$;
commit;

-- A signed-in role without a valid auth.uid() may not create orders.
begin;
set local role authenticated;
do $no_jwt$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.create_manual_checkout_order(
      '11111111-1111-4111-8111-111111111111',
      '55550000-0000-4000-8000-000000000099',
      '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000001","quantity":1,"unitPriceXaf":500}]'::jsonb
    );
  exception when sqlstate '28000' then v_rejected := true;
  end;
  if not v_rejected then raise exception 'No-JWT client was allowed to create order'; end if;
end;
$no_jwt$;
commit;

select 'PASS: Cross-shop and no-JWT access denied; stock insufficiency rolls back; TEST is isolated' as result;
