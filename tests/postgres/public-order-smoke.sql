-- Dedicated temporary PostgreSQL QR/social tests, never production.
-- Run after fixture, category stock, checkout, order approval and public link drafts.
-- Reuse stocked fixture categories; all public orders require owner approval.
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $owner$
declare
  v_link jsonb;
  v_second jsonb;
begin
  if public.get_checkout_public_link(
    '11111111-1111-4111-8111-111111111111') is not null then
    raise exception 'Public link should require explicit first-time activation';
  end if;

  v_link := public.configure_checkout_public_link(
    '11111111-1111-4111-8111-111111111111', true);
  v_second := public.get_checkout_public_link(
    '11111111-1111-4111-8111-111111111111');
  if v_link->>'enabled' <> 'true' or
     v_second->>'publicToken' <> v_link->>'publicToken' then
    raise exception 'Owner cannot read configured public link';
  end if;

  perform public.configure_checkout_public_link(
    '11111111-1111-4111-8111-111111111111', false);
  if (public.get_checkout_public_link(
      '11111111-1111-4111-8111-111111111111')->>'enabled') <> 'false' then
    raise exception 'Owner could not disable order link';
  end if;

  v_second := public.configure_checkout_public_link(
    '11111111-1111-4111-8111-111111111111', true);
  if v_second->>'publicToken' <> v_link->>'publicToken' then
    raise exception 'Enabling again incorrectly rotated permanent token';
  end if;
end;
$owner$;
commit;

select set_config(
  'covi.test.public_token',
  (select public_token::text from public.checkout_public_links
   where shop_id='11111111-1111-4111-8111-111111111111'),
  false
);

begin;
set local role anon;
do $visitor$
declare
  v_catalog jsonb;
  v_created jsonb;
  v_retried jsonb;
  v_rejected boolean;
  v_lines jsonb :=
    '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000001","quantity":1,"unitPriceXaf":2000}]'::jsonb;
begin
  v_catalog := public.get_checkout_public_catalog(
    current_setting('covi.test.public_token')::uuid);
  if v_catalog->>'shopName' <> 'Boutique A' or
     jsonb_array_length(v_catalog->'categories') <> 2 then
    raise exception 'Anonymous category catalog invalid or reveals TEST categories: %',v_catalog;
  end if;
  if v_catalog::text like '%quantity_on_hand%' or v_catalog::text like '%owner_id%' then
    raise exception 'Anonymous catalog leaked protected data';
  end if;

  v_created := public.submit_checkout_public_order(
    current_setting('covi.test.public_token')::uuid, 'qr',
    '77770000-0000-4000-8000-000000000001',
    v_lines, null, 'Je suis en caisse', 'pickup'
  );
  if v_created->>'status' <> 'submitted' or
     (v_created->>'amountXaf')::bigint <> 2000 then
    raise exception 'Guest did not create a submitted request: %',v_created;
  end if;

  v_retried := public.submit_checkout_public_order(
    current_setting('covi.test.public_token')::uuid, 'qr',
    '77770000-0000-4000-8000-000000000001',
    v_lines, null, 'Je suis en caisse', 'pickup'
  );
  if v_retried->>'orderId' <> v_created->>'orderId' then
    raise exception 'Public network retry created another order';
  end if;

  -- QR/social customers cannot bypass the owner approval or record "paid".
  v_rejected := false;
  begin
    perform public.approve_manual_checkout_order(
      '11111111-1111-4111-8111-111111111111',
      (v_created->>'orderId')::uuid
    );
  exception when insufficient_privilege then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Visitor approved order without owner'; end if;

  v_rejected := false;
  begin
    perform public.confirm_manual_checkout_payment(
      '11111111-1111-4111-8111-111111111111',
      (v_created->>'orderId')::uuid,
      '77770000-0000-4000-8000-000000000002',
      'Client', 'mobile_money', null
    );
  exception when insufficient_privilege then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Visitor confirmed their own payment'; end if;

  v_rejected := false;
  begin
    perform public.submit_checkout_public_order(
      current_setting('covi.test.public_token')::uuid, 'social',
      '77770000-0000-4000-8000-000000000003',v_lines,
      null, 'Livraison', 'delivery'
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Remote delivery accepted without contact phone'; end if;

  v_rejected := false;
  begin
    perform public.submit_checkout_public_order(
      'ffffffff-ffff-4fff-8fff-ffffffffffff', 'qr',
      '77770000-0000-4000-8000-000000000004',v_lines
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Unknown permanent link accepted'; end if;
end;
$visitor$;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $owner$
declare
  v_order uuid;
  v_approved jsonb;
  v_paid jsonb;
  v_old uuid;
  v_new jsonb;
begin
  select id into v_order from public.checkout_orders
  where creation_operation_id='77770000-0000-4000-8000-000000000001';
  if v_order is null then raise exception 'Owner cannot find public request'; end if;

  v_approved := public.approve_manual_checkout_order(
    '11111111-1111-4111-8111-111111111111',v_order);
  if v_approved->>'status' <> 'approved' then
    raise exception 'Owner cannot approve public checkout';
  end if;
  v_paid := public.confirm_manual_checkout_payment(
    '11111111-1111-4111-8111-111111111111',
    v_order,'77770000-0000-4000-8000-000000000005',
    'Marie Lou','cash',null
  );
  if v_paid->>'cashierFirstName' <> 'Marie Lou' then
    raise exception 'Receipt does not identify actual cashier';
  end if;

  v_old := current_setting('covi.test.public_token')::uuid;
  v_new := public.rotate_checkout_public_link(
    '11111111-1111-4111-8111-111111111111');
  if (v_new->>'publicToken')::uuid = v_old then
    raise exception 'Rotating public link reused same public token';
  end if;
end;
$owner$;
commit;

begin;
set local role anon;
do $old_link$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.get_checkout_public_catalog(
      current_setting('covi.test.public_token')::uuid
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Rotated token still grants access'; end if;
end;
$old_link$;
commit;

select 'PASS: Public QR order created once, owner alone approves/pays, invalid link rejected' as result;
