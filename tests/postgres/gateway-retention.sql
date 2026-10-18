-- Disposable PostgreSQL ONLY: rate-limit metadata expires, receipts never do.
-- This test must run after other gateway quota tests.
insert into public.checkout_gateway_rate_windows(digest,bucket_kind,bucket_start,hits)
values
  (repeat('e',64), 'catalog_source_minute', clock_timestamp() - interval '10 days', 1),
  (repeat('f',64), 'catalog_source_minute', clock_timestamp(), 1);

insert into public.checkout_public_rate_windows(shop_id,bucket_kind,bucket_start,submissions)
values
  ('11111111-1111-4111-8111-111111111111', 'minute',
   date_trunc('minute', clock_timestamp() - interval '12 days'), 1),
  ('11111111-1111-4111-8111-111111111111', 'minute',
   date_trunc('minute', clock_timestamp()), 1)
on conflict (shop_id,bucket_kind,bucket_start) do nothing;

begin;
set local role anon;
do $deny$
declare v_denied boolean := false;
begin
  begin
    perform public.prune_checkout_rate_windows();
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'Anonymous requester could delete protective quota data';
  end if;
end;
$deny$;
rollback;

begin;
set local role authenticated;
do $deny$
declare v_denied boolean := false;
begin
  begin
    perform public.prune_checkout_rate_windows();
  exception when insufficient_privilege then
    v_denied := true;
  end;
  if not v_denied then
    raise exception 'Signed-in customer could prune quota data';
  end if;
end;
$deny$;
rollback;

begin;
set local role service_role;
do $prune$
declare v_result jsonb;
begin
  v_result := public.prune_checkout_rate_windows();
  if (v_result->>'gatewayWindowsPruned')::bigint < 1 or
     (v_result->>'shopWindowsPruned')::bigint < 1 then
    raise exception 'Old quota buckets were not pruned: %',v_result;
  end if;
end;
$prune$;
commit;

do $check$
begin
  if exists(select 1 from public.checkout_gateway_rate_windows
    where digest=repeat('e',64)) then
    raise exception 'Old gateway fingerprint unexpectedly retained';
  end if;
  if not exists(select 1 from public.checkout_gateway_rate_windows
    where digest=repeat('f',64)) then
    raise exception 'Current gateway quota prematurely pruned';
  end if;
  if exists(select 1 from public.checkout_public_rate_windows
    where bucket_start < clock_timestamp() - interval '10 days') then
    raise exception 'Old shop rate windows unexpectedly retained';
  end if;
  if not exists(select 1 from public.checkout_public_rate_windows
    where shop_id='11111111-1111-4111-8111-111111111111'
      and bucket_kind='minute'
      and bucket_start=date_trunc('minute',clock_timestamp())) then
    raise exception 'Current shop rate window prematurely pruned';
  end if;
  if (select count(*) from public.manual_payment_confirmations) < 1 then
    raise exception 'Financial history disappeared during maintenance';
  end if;
end;
$check$;
select 'PASS: Anonymous users cannot prune, old counters removed, current counters and receipts preserved' as result;
