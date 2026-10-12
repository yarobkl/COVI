-- Runs in disposable covi_ci AFTER manual-checkout-smoke.sql.
insert into public.stock_categories
  (id, shop_id, category_key, display_name, quantity_on_hand, is_test)
values
  ('aaaaaaaa-0000-4000-8000-000000000009',
   '11111111-1111-4111-8111-111111111111',
   'vestes', 'Vestes', 1, false),
  ('aaaaaaaa-0000-4000-8000-000000000010',
   '11111111-1111-4111-8111-111111111111',
   'pantalons', 'Pantalons', 2, false);

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', true);

do $prepare$
declare
  v_shop uuid := '11111111-1111-4111-8111-111111111111';
  v_a jsonb;
  v_b jsonb;
  v_lines jsonb :=
    '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000009","quantity":1,"unitPriceXaf":5000}]'::jsonb;
begin
  v_a := public.create_manual_checkout_order(
    v_shop, '33330000-0000-4000-8000-000000000001', v_lines
  );
  v_b := public.create_manual_checkout_order(
    v_shop, '33330000-0000-4000-8000-000000000002', v_lines
  );
  if v_a->>'orderId' = v_b->>'orderId' then
    raise exception 'Race fixtures were not distinct orders';
  end if;
  perform public.approve_manual_checkout_order(v_shop, (v_a->>'orderId')::uuid);
  perform public.approve_manual_checkout_order(v_shop, (v_b->>'orderId')::uuid);

  -- Separate scenario: retrying the SAME order twice concurrently must
  -- return one persistent receipt, not create another sale.
  perform public.approve_manual_checkout_order(v_shop,
    (public.create_manual_checkout_order(
      v_shop, '33330000-0000-4000-8000-000000000003',
      '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000010","quantity":1,"unitPriceXaf":6000}]'::jsonb
    )->>'orderId')::uuid
  );

  if (select quantity_on_hand from public.stock_categories
      where id = 'aaaaaaaa-0000-4000-8000-000000000009') <> 1 then
    raise exception 'Approval unexpectedly reserved or decremented the final garment';
  end if;
end;
$prepare$;
commit;
select 'PASS: Two approved orders compete for one remaining garment' as result;
