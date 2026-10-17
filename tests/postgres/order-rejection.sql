-- Disposable covi_ci only. Owner rejection must never move stock or money.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $review$
declare
  v_shop uuid := '11111111-1111-4111-8111-111111111111';
  v_created jsonb;
  v_order uuid;
  v_rejected jsonb;
  v_unchanged integer;
  v_sales_before bigint;
  v_denied boolean := false;
begin
  select quantity_on_hand into v_unchanged from public.stock_categories
  where id='aaaaaaaa-0000-4000-8000-000000000002';
  select count(*) into v_sales_before from public.sales;
  v_created := public.create_manual_checkout_order(
    v_shop, 'f2222222-2222-4222-8222-222222222222',
    '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000002","quantity":1,"unitPriceXaf":5000}]'::jsonb
  );
  v_order := (v_created->>'orderId')::uuid;
  v_rejected := public.reject_checkout_order(v_shop, v_order);
  if v_rejected->>'status' <> 'cancelled' then
    raise exception 'Rejected order still pending';
  end if;
  if public.reject_checkout_order(v_shop, v_order) is distinct from v_rejected then
    raise exception 'Reject retry was not idempotent';
  end if;

  if (select rejected_by from public.checkout_orders where id=v_order)
       <> 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
     or (select rejected_at from public.checkout_orders where id=v_order) is null then
    raise exception 'Rejection audit identity/time missing';
  end if;
  begin
    perform public.approve_manual_checkout_order(v_shop, v_order);
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'Rejected order was approved'; end if;
  v_denied := false;
  begin
    perform public.confirm_manual_checkout_payment(
      v_shop, v_order, 'f3333333-3333-4333-8333-333333333333',
      'Awa', 'cash', null);
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'Rejected order was paid'; end if;
  if (select quantity_on_hand from public.stock_categories
      where id='aaaaaaaa-0000-4000-8000-000000000002') <> v_unchanged
      or (select count(*) from public.sales) <> v_sales_before then
    raise exception 'Rejection changed stock or sales';
  end if;
end;
$review$;
rollback;

-- Cross-shop account cannot reject another boutique's order.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
do $cross$
declare v_denied boolean := false;
begin
  begin
    perform public.reject_checkout_order(
      '11111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-111111111111');
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'Another shop owner can reject order'; end if;
end;
$cross$;
rollback;

begin;
set local role anon;
do $guest$
declare v_denied boolean := false;
begin
  begin
    perform public.reject_checkout_order(
      '11111111-1111-4111-8111-111111111111',
      '11111111-1111-4111-8111-111111111111');
  exception when insufficient_privilege then v_denied := true;
  end;
  if not v_denied then raise exception 'Guest rejected a shop order'; end if;
end;
$guest$;
rollback;

select 'PASS: Owner-only rejection audited, idempotent, no sale or stock movement' as result;
