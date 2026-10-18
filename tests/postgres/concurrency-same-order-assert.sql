-- After two connections tried the exact same payment UUID and order.
do $test$
declare
  v_order uuid;
  v_shop uuid := '11111111-1111-4111-8111-111111111111';
  v_count integer;
  v_quantity integer;
begin
  select id into v_order from public.checkout_orders
   where creation_operation_id='33330000-0000-4000-8000-000000000003';

  if (select status from public.checkout_orders where id=v_order)<>'paid' then
    raise exception 'Same-order concurrent payment did not complete';
  end if;

  select count(*) into v_count from public.manual_payment_confirmations
    where order_id=v_order
      and cashier_first_name='Marie Lou'
      and operation_id='44440000-0000-4000-8000-000000000003';
  if v_count<>1 then raise exception 'Expected exactly one receipt for duplicate clicks'; end if;

  select count(*) into v_count from public.stock_movements
    where category_id='aaaaaaaa-0000-4000-8000-000000000010'
       and movement_type='sale' and quantity_delta=-1;
  if v_count<>1 then raise exception 'Duplicate payment changed stock twice'; end if;

  select quantity_on_hand into v_quantity from public.stock_categories
    where id='aaaaaaaa-0000-4000-8000-000000000010';
  if v_quantity<>1 then raise exception 'Duplicate payment incorrectly changed inventory to %',v_quantity; end if;

  select count(*) into v_count from public.sales
    where client_operation_id='44440000-0000-4000-8000-000000000003';
  if v_count<>1 then raise exception 'Duplicate payment inserted another financial sale'; end if;
end;
$test$;
select 'PASS: Concurrent identical confirmations yield one sale, one receipt and one stock decrement' as result;
