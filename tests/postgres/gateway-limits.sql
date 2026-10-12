-- Disposable PostgreSQL: atomic server-only quotas, never run on production.
begin;
set local role anon;
do $deny$
declare denied boolean := false;
begin
  begin
    perform public.consume_checkout_gateway_quota(repeat('a',64), 'order_source_minute');
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then raise exception 'Anonymous guest can consume privileged quota'; end if;
end;
$deny$;
rollback;

begin;
set local role authenticated;
do $deny$
declare denied boolean := false;
begin
  begin
    perform public.consume_checkout_gateway_quota(repeat('a',64), 'order_source_minute');
  exception when insufficient_privilege then denied := true;
  end;
  if not denied then raise exception 'Authenticated browser can consume gateway quota'; end if;
end;
$deny$;
rollback;

begin;
set local role service_role;
do $quota$
declare i integer;
  result boolean;
  invalid_rejected boolean := false;
begin
  for i in 1..5 loop
    result := public.consume_checkout_gateway_quota(repeat('a',64), 'order_source_minute');
    if result is distinct from true then raise exception 'Source blocked too early'; end if;
  end loop;
  if public.consume_checkout_gateway_quota(repeat('a',64), 'order_source_minute')
    is distinct from false then
    raise exception 'Per-source order quota bypassed';
  end if;
  if public.consume_checkout_gateway_quota(repeat('b',64), 'order_source_minute')
    is distinct from true then
    raise exception 'Distinct source improperly blocked';
  end if;
  for i in 1..30 loop
    result := public.consume_checkout_gateway_quota(repeat('c',64), 'catalog_source_minute');
    if result is distinct from true then raise exception 'Catalogue blocked early'; end if;
  end loop;
  if public.consume_checkout_gateway_quota(repeat('c',64), 'catalog_source_minute')
    is distinct from false then
    raise exception 'Catalogue source ceiling bypassed';
  end if;
  begin
    perform public.consume_checkout_gateway_quota(repeat('d',64), 'unlimited');
  exception when others then invalid_rejected := true;
  end;
  if not invalid_rejected then raise exception 'Arbitrary rate limit kind accepted'; end if;
end;
$quota$;
commit;
select 'PASS: Gateway limits are atomic and server-only' as result;
