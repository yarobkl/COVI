-- Shared management login: cashier profiles with PIN, sales attribution and no data leaks.
-- Test fixtures only. All changes rolled back.
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(p_ok boolean,p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %',p_label; end if;
  raise notice 'ok %',p_label;
end $$;
\set shop '10000000-0000-0000-0000-0000000000e1'
\set owner '00000000-0000-0000-0000-0000000000e1'
\set product '30000000-0000-0000-0000-0000000000e1'
insert into auth.users(id) values (:'owner');
insert into public.shops(id,owner_id,name)
values (:'shop',:'owner','Boutique de test PIN');
insert into public.products(id,shop_id,name,initial_sale_price,quantity_on_hand)
values (:'product',:'shop','Jean bleu',10000,5);

set local role authenticated;
select set_config('request.jwt.claim.sub',:'owner',true);
select pg_temp.check(not has_table_privilege('authenticated','public.shop_cashier_profiles','select')
  and not has_table_privilege('authenticated','public.shop_cashier_tills','select'),
  'No direct PIN hash or till token access');
select pg_temp.check(not has_function_privilege('anon','public.create_shared_cashier(uuid,text,text,numeric,boolean)','execute'),
  'Anonymous cannot create cashier profiles');

select public.create_shared_cashier(:'shop','Awa','5937',10,false)->>'id' as awa \gset
select public.create_shared_cashier(:'shop','Bema','7391',0,false)->>'id' as bema \gset
select pg_temp.check((select count(*) from public.shop_cashier_profiles where shop_id=:'shop')=2,
  'Two PIN-only cashiers created');
select pg_temp.check(public.list_shared_cashiers(:'shop')::text !~ '5937|7391|pin_hash',
  'PIN secrets not exposed in list');
select public.set_owner_pin(:'shop','4876');

select pg_temp.check(
  public.open_shared_cashier_till(:'shop',:'awa','9999')->>'status'='invalid',
  'Invalid cashier PIN rejected');
select (public.open_shared_cashier_till(:'shop',:'awa','5937'))->>'token' as awa_token \gset
select pg_temp.check(char_length(:'awa_token')=64,'Cashier receives an opaque till token');

select public.record_sale(:'shop',:'product',1,9000,'cash',
  '40000000-0000-0000-0000-0000000000e1',:'awa_token') as sale1 \gset
select pg_temp.check(
  (select cashier_profile_id=:'awa' and seller_id=:'owner' from public.sales where id=:'sale1')
  and (select quantity_on_hand=4 from public.products where id=:'product'),
  'Awa sale correctly attributed and stock decremented once');

select (public.open_shared_cashier_till(:'shop',:'bema','7391'))->>'token' as bema_token \gset
select public.record_sale(:'shop',:'product',1,10000,'cash',
  '40000000-0000-0000-0000-0000000000e2',:'bema_token') as sale2 \gset
select pg_temp.check((select cashier_profile_id=:'bema' from public.sales where id=:'sale2'),
  'Bema sale attributed to Bema');
select pg_temp.check(
  (select count(distinct cashier_profile_id)=2 from public.sales where shop_id=:'shop'),
  'Manager login tracks both cashier identities independently');

select pg_temp.check(public.leave_counter_mode(:'shop','0000',:'bema_token')->>'status'='invalid',
  'Wrong owner PIN refuses return');
select pg_temp.check(public.leave_counter_mode(:'shop','4876',:'bema_token')->>'status'='ok',
  'Correct owner PIN allows return');
select pg_temp.check(public.close_shared_cashier_till(:'shop',:'bema_token') is false,
  'Manager PIN closes cashier till on return');
rollback;
