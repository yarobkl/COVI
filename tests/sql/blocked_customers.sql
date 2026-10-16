-- Modération des commandes en ligne : bloquer un client abusif, le débloquer.
-- Données de test uniquement ; tout est annulé.
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok %', p_label;
end $$;
create function pg_temp.order_from(p_token uuid, p_phone text) returns jsonb
language sql as $$
  select public.submit_public_order(p_token, 'social', gen_random_uuid(), 'Client', p_phone,
    'pickup', null, 'cash', null,
    pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('description', 'Sac', 'quantity', 1)))
$$;
create function pg_temp.refused(p_token uuid, p_phone text) returns boolean
language plpgsql as $$
begin
  perform pg_temp.order_from(p_token, p_phone);
  return false;
exception when others then
  if sqlerrm <> 'Order link unavailable' then raise exception 'unexpected: %', sqlerrm; end if;
  return true;
end $$;

\set shop '10000000-0000-0000-0000-0000000000b1'
\set other '10000000-0000-0000-0000-0000000000b2'
\set owner '00000000-0000-0000-0000-0000000000b1'
\set stranger '00000000-0000-0000-0000-0000000000b2'
insert into auth.users(id) values (:'owner'), (:'stranger');
insert into public.shops(id, owner_id, name) values
  (:'shop', :'owner', 'Boutique modérée'), (:'other', :'stranger', 'Autre boutique');

set local role authenticated;
select set_config('request.jwt.claim.sub', :'owner', true);
select (public.configure_public_order_channel(:'shop', true, false, null)) ->> 'token' as token \gset
select set_config('request.jwt.claim.sub', :'stranger', true);
select (public.configure_public_order_channel(:'other', true, false, null)) ->> 'token' as other_token \gset

set local role service_role;
select (pg_temp.order_from(:'token', '+242 06 123 45 67')) ->> 'orderId' as order_id \gset

set local role authenticated;
select pg_temp.check(not has_function_privilege('anon', 'public.block_order_customer(uuid)',
  'execute'), 'Anonymous cannot block');
select set_config('request.jwt.claim.sub', :'stranger', true);
select set_config('covi.test_order', :'order_id', true);
do $$
declare v_denied boolean := false;
begin
  begin
    perform public.block_order_customer(current_setting('covi.test_order')::uuid);
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'FAIL stranger blocked a customer of another shop'; end if;
end $$;
select set_config('request.jwt.claim.sub', :'owner', true);
select public.block_order_customer(:'order_id');
reset role;
select pg_temp.check((select phone_key = '061234567' from public.shop_blocked_customers
  where shop_id = :'shop'), 'Number stored on its last 9 digits');
set local role authenticated;
select pg_temp.check(public.list_blocked_customers(:'shop') -> 0 ->> 'phone' = '+242 06 123 45 67',
  'Owner sees the blocked number');

reset role;
select pg_temp.check((select status = 'rejected' from public.public_orders where id = :'order_id'),
  'The open order of the blocked customer is refused');
set local role service_role;
select pg_temp.check(pg_temp.refused(:'token', '061234567'),
  'Blocked customer cannot order again, whatever the number format');
select pg_temp.check(pg_temp.refused(:'token', '+242061234567'), 'Same with the country code');
select pg_temp.check(pg_temp.order_from(:'token', '+242 05 555 55 55') ? 'orderId',
  'Other customers still order');
select pg_temp.check(pg_temp.order_from(:'other_token', '061234567') ? 'orderId',
  'A block applies to one shop only');

set local role authenticated;
select set_config('request.jwt.claim.sub', :'stranger', true);
do $$
declare v_denied boolean := false;
begin
  begin
    perform public.list_blocked_customers('10000000-0000-0000-0000-0000000000b1');
  exception when others then v_denied := true;
  end;
  if not v_denied then raise exception 'FAIL stranger read the block list'; end if;
end $$;
select set_config('request.jwt.claim.sub', :'owner', true);
select public.unblock_customer(:'shop', '061234567');
set local role service_role;
select pg_temp.check(pg_temp.order_from(:'token', '061234567') ? 'orderId',
  'Unblocked customer can order again');
rollback;
