-- After two independent orders attempted to sell the final "vestes" item.
do $test$
declare
  v_shop uuid := '11111111-1111-4111-8111-111111111111';
  v_paid integer;
  v_other integer;
  v_stock integer;
  v_sales integer;
  v_moves integer;
begin
  select count(*) filter (where status='paid'),
         count(*) filter (where status='approved')
    into v_paid, v_other
    from public.checkout_orders
    where shop_id=v_shop
      and creation_operation_id in (
        '33330000-0000-4000-8000-000000000001',
        '33330000-0000-4000-8000-000000000002'
      );
  if v_paid<>1 or v_other<>1 then
    raise exception 'Oversell: expected exactly one paid, one approved, got paid %, approved %', v_paid, v_other;
  end if;

  select quantity_on_hand into v_stock from public.stock_categories
    where id='aaaaaaaa-0000-4000-8000-000000000009';
  if v_stock<>0 then raise exception 'Expected 0 vestes, got %', v_stock; end if;
  select count(*) into v_moves from public.stock_movements
    where category_id='aaaaaaaa-0000-4000-8000-000000000009'
      and movement_type='sale' and quantity_delta=-1;
  if v_moves<>1 then raise exception 'Expected exactly one last-item stock movement'; end if;
  select count(*) into v_sales from public.manual_payment_confirmations
    where order_id in (
      select id from public.checkout_orders
      where creation_operation_id in (
        '33330000-0000-4000-8000-000000000001',
        '33330000-0000-4000-8000-000000000002'
      )
    );
  if v_sales<>1 then raise exception 'Expected exactly one confirmation for the last garment'; end if;
end;
$test$;
select 'PASS: Two simultaneous competing orders cannot oversell the last garment' as result;
