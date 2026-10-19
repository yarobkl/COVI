-- Reproducible website connection and order tests; all changes rolled back.
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(p_ok boolean,p_label text) returns void
language plpgsql as $$
begin if p_ok is not true then raise exception 'FAIL %',p_label; end if;
raise notice 'ok %',p_label; end $$;
create function pg_temp.fails(p_sql text,p_message text) returns boolean
language plpgsql as $$
begin execute p_sql; return false;
exception when others then
if sqlerrm not like '%'||p_message||'%' then
raise exception 'expected %, got %',p_message,sqlerrm; end if; return true; end $$;
\set owner 'a1000000-0000-4000-8000-000000000001'
\set other 'a1000000-0000-4000-8000-000000000002'
\set shop 'a2000000-0000-4000-8000-000000000001'
\set other_shop 'a2000000-0000-4000-8000-000000000002'
\set product 'a3000000-0000-4000-8000-000000000001'
insert into auth.users(id) values(:'owner'),(:'other');
insert into public.shops(id,owner_id,name) values
(:'shop',:'owner','Shop Site'),(:'other_shop',:'other','Other Shop');
insert into public.products(id,shop_id,name,initial_sale_price,quantity_on_hand,is_test)
values(:'product',:'shop','Pantalon',10000,8,false);
set local role authenticated;
select set_config('request.jwt.claim.sub',:'owner',true);
select pg_temp.check(not has_table_privilege('authenticated','public.website_connections','SELECT'),
  'Website key hashes never readable');
select pg_temp.check(not has_function_privilege('anon',
  'public.create_website_connection(uuid,text,text)','EXECUTE'), 'Anonymous cannot create keys');
select pg_temp.check(not has_function_privilege('authenticated',
  'public.import_website_order(uuid,text,text,text,text,text,text,jsonb)','EXECUTE'),
  'Owner session cannot impersonate website gateway');
select public.create_website_connection(:'shop','WooCommerce','https://shop.example')->>'secret' as token
\gset
select pg_temp.check(:'token' ~ '^covi_site_[0-9a-f]{64}$','Token is random-sized');
select pg_temp.check(pg_catalog.jsonb_array_length(public.list_website_connections(:'shop'))=1,
  'Owner lists site metadata');
select set_config('request.jwt.claim.sub',:'other',true);
select pg_temp.check(pg_temp.fails($q$select public.list_website_connections(
'a2000000-0000-4000-8000-000000000001')$q$,'Shop not found'),'Other shop denied');
reset role;
set local role service_role;
select public.authorize_website_connection(:'token')->>'id' as connection_id
\gset
select pg_temp.check(:'connection_id' ~ '^[a-f0-9-]{36}$','Site authentication works');
select pg_temp.check(public.consume_website_api_quota(:'connection_id','orders'), 'Quota available');
select pg_temp.check(
 public.import_website_order(:'connection_id','WC-501','Awa','+242060000000','mobile_money','pickup',
 null,pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
 'productId',:'product','quantity',2)))->>'status'='new','New website order received');
select pg_temp.check(
 public.import_website_order(:'connection_id','WC-501','Awa','+242060000000','mobile_money','pickup',
 null,pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
 'productId',:'product','quantity',2)))->>'alreadyImported'='true','Retry is idempotent');
select pg_temp.check((select count(*)=1 from public.public_orders
 where channel='website' and shop_id=:'shop'), 'Only one order persisted');
select pg_temp.check((select quantity_on_hand=8 from public.products where id=:'product'),
 'No stock decremented before payment');
select pg_temp.check((select count(*)=0 from public.sales where shop_id=:'shop'),
 'No fictitious sale created');
select pg_temp.check(
 (public.get_website_order_state(:'connection_id','WC-501')->>'status')='new',
 'Website can poll order state');
select pg_temp.check(pg_temp.fails($q$select public.import_website_order(
  'a2000000-0000-4000-8000-000000000002','WC-502','Awa','+242060000000',
  'cash','pickup',null,'[]'::jsonb)$q$,'Website access denied'),
  'A foreign identifier cannot authorize another tenant');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub',:'owner',true);
select pg_temp.check(public.revoke_website_connection(:'connection_id'), 'Owner revoked site');
reset role;
set local role service_role;
select pg_temp.check(public.authorize_website_connection(:'token') is null,'Revocation immediate');
rollback;
