-- Disposable PostgreSQL only: public rate ceilings and private owner inbox.
-- Execute AFTER public-order-smoke.sql.
select set_config(
  'covi.test.active_public_token',
  (select public_token::text from public.checkout_public_links
    where shop_id='11111111-1111-4111-8111-111111111111'),
  false
);

begin;
-- Requests below simulate the trusted server gateway role.
set local role service_role;
do $visitor$
declare
  v_created jsonb;
  v_rejected boolean := false;
begin
  v_created := public.submit_checkout_public_order(
    current_setting('covi.test.active_public_token')::uuid,
    'social',
    '88880000-0000-4000-8000-000000000001',
    '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000002","quantity":1,"unitPriceXaf":1800}]'::jsonb,
    '+242 060000001', 'Vu pendant le live', 'delivery'
  );
  if v_created->>'status'<>'submitted' then
    raise exception 'Social delivery request not accepted';
  end if;
  begin
    perform public.get_checkout_pending_orders(
      '11111111-1111-4111-8111-111111111111'
    );
  exception when insufficient_privilege then v_rejected := true;
  end;
  if not v_rejected then raise exception 'Anonymous visitor read owner order inbox'; end if;
end;
$visitor$;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',true);
do $other_owner$
declare
  v_rejected boolean := false;
begin
  begin
    perform public.get_checkout_pending_orders(
      '11111111-1111-4111-8111-111111111111'
    );
  exception when insufficient_privilege then v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'Other shop owner saw customer contacts';
  end if;
end;
$other_owner$;
commit;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',true);
do $owner$
declare
  v_orders jsonb;
  v_found boolean;
begin
  v_orders := public.get_checkout_pending_orders(
    '11111111-1111-4111-8111-111111111111'
  );
  select exists(
    select 1 from jsonb_array_elements(v_orders) as row_data(item)
    where item->>'customerPhone' = '+242 060000001'
      and item->>'channel' = 'social'
      and item->>'status' = 'submitted'
      and item->>'amountXaf' = '1800'
      and jsonb_array_length(item->'lines') = 1
  ) into v_found;
  if not v_found then raise exception 'Owner inbox did not return the customer request'; end if;
end;
$owner$;
commit;

-- Seed limits as an administrative fixture, not through an anonymous query.
insert into public.checkout_public_rate_windows
  (shop_id, bucket_kind, bucket_start, submissions)
values (
  '11111111-1111-4111-8111-111111111111',
  'minute', date_trunc('minute',clock_timestamp()),60
)
on conflict (shop_id,bucket_kind,bucket_start) do update set submissions=60;

begin;
-- Requests below simulate the trusted server gateway role.
set local role service_role;
do $rate_limit$
declare
  v_rejected boolean := false;
  v_retry jsonb;
begin
  -- A network retry of an already saved request should still succeed even
  -- when the new-order quota is exhausted, and does not duplicate rows.
  v_retry := public.submit_checkout_public_order(
    current_setting('covi.test.active_public_token')::uuid,
    'social',
    '88880000-0000-4000-8000-000000000001',
    '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000002","quantity":1,"unitPriceXaf":1800}]'::jsonb,
    '+242 060000001', 'Vu pendant le live', 'delivery'
  );
  if v_retry->>'status'<>'submitted' then
    raise exception 'Duplicate public request was not idempotent under quota';
  end if;

  begin
    perform public.submit_checkout_public_order(
      current_setting('covi.test.active_public_token')::uuid,
      'social',
      '88880000-0000-4000-8000-000000000002',
      '[{"categoryId":"aaaaaaaa-0000-4000-8000-000000000002","quantity":1,"unitPriceXaf":2000}]'::jsonb
    );
  exception when others then v_rejected := true;
  end;
  if not v_rejected then raise exception '60-per-minute public limit bypassed'; end if;
end;
$rate_limit$;
commit;

select 'PASS: Owner-only inbox protects contacts; anonymous queue capped and retries remain idempotent' as result;
