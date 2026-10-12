-- Used by tests/run-postgres-checkout.sh in TWO REAL concurrent psql sessions.
-- created_op/payment_op/money parameters are test-only psql variables.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);
select public.confirm_manual_checkout_payment(
  '11111111-1111-4111-8111-111111111111'::uuid,
  (select id from public.checkout_orders
   where shop_id = '11111111-1111-4111-8111-111111111111'
     and creation_operation_id = :'created_op'::uuid),
  :'payment_op'::uuid,
  'Marie Lou',
  'cash',
  null
) as payment_confirmation;
-- Keep the row locks held long enough to force the other connection to wait.
select pg_sleep(1.5);
commit;
