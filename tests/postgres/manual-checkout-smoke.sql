-- Run ONLY after applying SQL drafts to an ephemeral test database.
-- This is a deterministic smoke scenario; concurrent races are separate.
insert into public.stock_categories
  (id, shop_id, category_key, display_name, quantity_on_hand, is_test)
values
  ('aaaaaaaa-0000-4000-8000-000000000001', '11111111-1111-4111-8111-111111111111', 'robes', 'Robes', 5, false),
  ('aaaaaaaa-0000-4000-8000-000000000002', '11111111-1111-4111-8111-111111111111', 'chemises', 'Chemises', 4, false),
  ('aaaaaaaa-0000-4000-8000-000000000003', '11111111-1111-4111-8111-111111111111', 'robes', 'Robes TEST', 2, true),
  ('bbbbbbbb-0000-4000-8000-000000000001', '22222222-2222-4222-8222-222222222222', 'robes', 'Robes B', 7, false);

grant select on all tables in schema public to authenticated;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

do $smoke$
declare
  v_shop uuid := '11111111-1111-4111-8111-111111111111';
  v_other_shop uuid := '22222222-2222-4222-8222-222222222222';
  v_operation uuid := '11110000-0000-4000-8000-000000000001';
  v_pay_operation uuid := '22220000-0000-4000-8000-000000000001';
  v_lines jsonb := '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000001","quantity":2,"unitPriceXaf":3500},{"categoryId":"aaaaaaaa-0000-4000-8000-000000000002","quantity":1,"unitPriceXaf":5000}]'::jsonb;
  v_created jsonb;
  v_retried jsonb;
  v_approved jsonb;
  v_paid jsonb;
  v_paid_again jsonb;
  v_order uuid;
  v_counter integer;
  v_rejected boolean;
begin
  v_created := public.create_manual_checkout_order(
    v_shop, v_operation, v_lines, false, null, 'Vente en boutique', 'pickup'
  );
  if v_created->>'status' <> 'submitted' or (v_created->>'amountXaf')::bigint <> 12000 then
    raise exception 'Creation did not return submitted/12000: %', v_created;
  end if;
  v_order := (v_created->>'orderId')::uuid;

  -- Same exact payload in a different line order: same order and no second row.
  v_retried := public.create_manual_checkout_order(
    v_shop, v_operation, (
      select jsonb_agg(item order by item->>'categoryId' desc)
      from jsonb_array_elements(v_lines) as e(item)
    ), false, null, 'Vente en boutique', 'pickup'
  );
  if v_retried->>'orderId' is distinct from v_created->>'orderId' then
    raise exception 'Retry created another order';
  end if;
  select count(*) into v_counter
    from public.checkout_orders where shop_id = v_shop and creation_operation_id = v_operation;
  if v_counter <> 1 then raise exception 'Duplicate manual order rows: %', v_counter; end if;

  v_rejected := false;
  begin
    perform public.create_manual_checkout_order(
      v_shop, v_operation,
      '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000001","quantity":1,"unitPriceXaf":3500}]'::jsonb,
      false, null, 'Vente en boutique', 'pickup'
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Conflicting order retry was accepted'; end if;

  -- Cross-shop access must fail even for a valid signed-in user.
  v_rejected := false;
  begin
    perform public.create_manual_checkout_order(
      v_other_shop, '11110000-0000-4000-8000-000000000009',
      '[{"categoryId":"bbbbbbbb-0000-4000-8000-000000000001","quantity":1,"unitPriceXaf":4000}]'::jsonb
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Cross-shop access succeeded'; end if;

  -- A real order cannot include a TEST inventory category.
  v_rejected := false;
  begin
    perform public.create_manual_checkout_order(
      v_shop, '11110000-0000-4000-8000-000000000008',
      '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000003","quantity":1,"unitPriceXaf":3000}]'::jsonb,
      false
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'TEST category used in real order'; end if;

  v_approved := public.approve_manual_checkout_order(v_shop, v_order);
  if v_approved->>'status' <> 'approved' then raise exception 'Approval failed'; end if;
  if (select quantity_on_hand from public.stock_categories
      where id = 'aaaaaaaa-0000-4000-8000-000000000001') <> 5 then
    raise exception 'Approval decremented inventory';
  end if;

  -- Approval retry is idempotent.
  v_approved := public.approve_manual_checkout_order(v_shop, v_order);
  if v_approved->>'status' <> 'approved' then
    raise exception 'Second approval changed status';
  end if;

  -- No provider API: seller declares money received and types the first name.
  v_paid := public.confirm_manual_checkout_payment(
    v_shop, v_order, v_pay_operation, 'Marie Lou', 'mobile_money', 'SMS-1234'
  );
  if v_paid->>'cashierFirstName' <> 'Marie Lou'
     or v_paid->>'method' <> 'mobile_money'
     or (v_paid->>'amountXaf')::bigint <> 12000
     or jsonb_array_length(v_paid->'lines') <> 2
     or left(v_paid->>'receiptNumber', 8) <> 'CV-2026-' then
    raise exception 'Saved receipt is incorrect: %', v_paid;
  end if;
  if (select quantity_on_hand from public.stock_categories
      where id = 'aaaaaaaa-0000-4000-8000-000000000001') <> 3 then
    raise exception 'Robes stock not updated exactly once';
  end if;
  if (select quantity_on_hand from public.stock_categories
      where id = 'aaaaaaaa-0000-4000-8000-000000000002') <> 3 then
    raise exception 'Chemises stock not updated exactly once';
  end if;

  -- Double-click and network retry must get the original receipt.
  v_paid_again := public.confirm_manual_checkout_payment(
    v_shop, v_order, v_pay_operation, 'Marie Lou', 'mobile_money', 'SMS-1234'
  );
  if v_paid_again is distinct from v_paid then
    raise exception 'Payment retry yielded a different receipt';
  end if;

  v_rejected := false;
  begin
    perform public.confirm_manual_checkout_payment(
      v_shop, v_order, v_pay_operation, 'Autre Personne', 'mobile_money', 'SMS-1234'
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Changed-cashier retry accepted'; end if;

  if (select count(*) from public.sales where shop_id = v_shop) <> 1 then
    raise exception 'Double sale was recorded';
  end if;
  if (select count(*) from public.stock_movements where shop_id = v_shop
      and movement_type = 'sale') <> 2 then
    raise exception 'Incorrect stock movement count';
  end if;
  if (select cashier_first_name from public.manual_payment_confirmations
      where order_id = v_order) <> 'Marie Lou' then
    raise exception 'Cashier name missing from durable receipt';
  end if;
end;
$smoke$;
commit;

-- Function EXECUTE must remain denied to anonymous clients.
begin;
set local role anon;
do $anon$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.approve_manual_checkout_order(
      '11111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-111111111111'
    );
  exception when insufficient_privilege then
    v_rejected := true;
  end;
  if not v_rejected then raise exception 'Anonymous client had payment permissions'; end if;
end;
$anon$;
commit;

select 'PASS: Manual order → approval → seller-confirmed payment → immutable receipt, no duplicates' as result;
