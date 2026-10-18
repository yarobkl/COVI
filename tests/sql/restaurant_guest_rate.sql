-- Test durable per-source quotas on disposable Postgres only.
\set ON_ERROR_STOP 1
begin;
do $scope$
begin
 if has_function_privilege('anon','public.restaurant_guest_rate_gate(text,text,text)','execute')
  or has_function_privilege('authenticated','public.restaurant_guest_rate_gate(text,text,text)','execute')
  then raise exception 'Guest limiter incorrectly exposed to clients'; end if;
end $scope$;
set local role service_role;
do $test$
declare n integer;
begin
 if public.restaurant_guest_rate_gate('bad',repeat('c',64),'join') then
  raise exception 'Invalid fingerprint accepted'; end if;
 for n in 1..12 loop
  if not public.restaurant_guest_rate_gate(repeat('a',64),repeat('b',64),'join') then
   raise exception 'Join % incorrectly limited',n; end if;
 end loop;
 if public.restaurant_guest_rate_gate(repeat('a',64),repeat('b',64),'join') then
  raise exception 'Excess failed PIN attempts are not throttled'; end if;
 if not public.restaurant_guest_rate_gate(repeat('c',64),repeat('b',64),'join') then
  raise exception 'Another client source incorrectly blocked before QR quota'; end if;
end $test$;
rollback;
