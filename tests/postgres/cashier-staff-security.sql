-- Run in disposable covi_ci AFTER all ordinary checkout audits.
-- Verifies invitation redemption, shop isolation, bcrypt PIN lockout,
-- employee-verified payment, atomic stock, retry and revocation.
insert into auth.users(id) values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc');
insert into public.stock_categories
 (id,shop_id,category_key,display_name,quantity_on_hand,is_test)
values ('cccccccc-0000-4000-8000-000000000001',
        '11111111-1111-4111-8111-111111111111',
        'cashier-test','Test caissier',2,false);

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $owner$
declare v_invite jsonb;
begin
  v_invite := public.create_checkout_cashier_invite(
    '11111111-1111-4111-8111-111111111111','Aminata');
  if v_invite->>'inviteCode' is null then raise exception 'Invite not created'; end if;
  perform set_config('covi.test.cashier_invite', v_invite->>'inviteCode', false);
end;
$owner$;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);
do $staff$
declare v_shop uuid := '11111111-1111-4111-8111-111111111111';
 v_id uuid; v_order jsonb; v_receipt jsonb;
 v_rejected boolean; v_invite text := current_setting('covi.test.cashier_invite');
begin
  if (public.redeem_checkout_cashier_invite(v_invite::uuid)->>'firstName') <> 'Aminata' then
    raise exception 'Staff invitation failed';
  end if;
  v_rejected := false;
  begin perform public.redeem_checkout_cashier_invite(v_invite::uuid);
  exception when others then v_rejected:=true; end;
  if not v_rejected then raise exception 'Reused invitation'; end if;

  if public.set_checkout_cashier_pin(v_shop,'654321') is distinct from true then
    raise exception 'PIN enrolment failed';
  end if;
  if jsonb_array_length(public.get_my_checkout_cashier_shops()) <> 1 then
    raise exception 'Member cannot see own cashier shop';
  end if;
  v_rejected := false;
  begin perform public.create_checkout_cashier_invite(v_shop,'Fake');
  exception when insufficient_privilege then v_rejected:=true; end;
  if not v_rejected then raise exception 'Staff able to create invitations'; end if;

  v_order := public.create_manual_checkout_order(v_shop,
    'cccc0000-0000-4000-8000-000000000001',
    '[{"categoryId":"cccccccc-0000-4000-8000-000000000001","quantity":1,"unitPriceXaf":5700}]'::jsonb);
  v_id := (v_order->>'orderId')::uuid;
  perform set_config('covi.test.cashier_order',v_id::text,false);
  if public.approve_manual_checkout_order(v_shop,v_id)->>'status' <> 'approved' then
    raise exception 'Staff cannot approve own order'; end if;

  for i in 1..5 loop
    v_receipt := public.confirm_manual_checkout_payment(v_shop,v_id,
      'cccc0000-0000-4000-8000-000000000002','Aminata','cash',null,'000000');
    if v_receipt->>'pinRejected' is distinct from 'true' then
      raise exception 'Invalid PIN accepted on attempt %',i; end if;
  end loop;
  v_receipt := public.confirm_manual_checkout_payment(v_shop,v_id,
    'cccc0000-0000-4000-8000-000000000002','Aminata','cash',null,'654321');
  if v_receipt->>'pinRejected' is distinct from 'true' then
    raise exception 'Correct PIN bypassed 15-minute lockout'; end if;
  if (select count(*) from public.manual_payment_confirmations where order_id=v_id) <> 0 then
    raise exception 'Unpaid order got a receipt'; end if;
end;
$staff$;
commit;

-- Simulate lockout timeout ONLY in this disposable test database.
update public.checkout_cashier_secrets
set blocked_until=now()-interval '1 minute',failed_attempts=0
where shop_id='11111111-1111-4111-8111-111111111111'
and user_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc';

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);
do $paid$
declare v_shop uuid := '11111111-1111-4111-8111-111111111111';
  v_id uuid := current_setting('covi.test.cashier_order')::uuid;
  v_receipt jsonb; v_retry jsonb; v_rejected boolean;
begin
  v_rejected:=false;
  begin perform public.confirm_manual_checkout_payment(v_shop,v_id,
    'cccc0000-0000-4000-8000-000000000002','Fake Name','cash',null,'654321');
  exception when others then v_rejected:=true; end;
  if not v_rejected then raise exception 'Staff first-name spoofing permitted'; end if;
  v_receipt := public.confirm_manual_checkout_payment(v_shop,v_id,
    'cccc0000-0000-4000-8000-000000000002','Aminata','cash',null,'654321');
  if v_receipt->>'receiptNumber' is null then raise exception 'Staff not paid'; end if;
  v_retry := public.confirm_manual_checkout_payment(v_shop,v_id,
    'cccc0000-0000-4000-8000-000000000002','Aminata','cash',null,'654321');
  if v_retry is distinct from v_receipt then raise exception 'Retry duplicate'; end if;
end;
$paid$;
commit;

do $assert$
begin
  if (select quantity_on_hand from public.stock_categories
    where id='cccccccc-0000-4000-8000-000000000001') <> 1 then
    raise exception 'Staff payment did not decrement stock exactly once'; end if;
  if (select count(*) from public.manual_payment_confirmations
    where order_id=current_setting('covi.test.cashier_order')::uuid
    and confirmed_by='cccccccc-cccc-4ccc-8ccc-cccccccccccc') <> 1 then
    raise exception 'Staff audit identity not preserved'; end if;
end;
$assert$;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
select public.set_checkout_cashier_active(
  '11111111-1111-4111-8111-111111111111',
  'cccccccc-cccc-4ccc-8ccc-cccccccccccc',false);
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','cccccccc-cccc-4ccc-8ccc-cccccccccccc',true);
do $disabled$
declare rejected boolean:=false;
begin
  begin perform public.get_checkout_pending_orders(
    '11111111-1111-4111-8111-111111111111');
  exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'Disabled staff can still read orders'; end if;
  if jsonb_array_length(public.get_my_checkout_cashier_shops()) <> 0 then
    raise exception 'Disabled staff portal still visible'; end if;
end;
$disabled$;
commit;

select 'PASS: Cashier invitation, personal bcrypt PIN, rate limits, audited sale and revocation' as result;
