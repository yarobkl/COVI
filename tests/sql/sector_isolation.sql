-- COVI restaurant/salon tenant isolation, executed on disposable PostgreSQL.
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin if ok is not true then raise exception 'FAIL %',label; end if; end $$;
create function pg_temp.expect_denied(sql_text text, label text) returns void language plpgsql as $$
declare code text;
begin
  begin execute sql_text;
  exception when others then
    get stacked diagnostics code = returned_sqlstate;
    if code='42501' then return; end if;
    raise exception 'FAIL %: unexpected SQLSTATE %',label,code;
  end;
  raise exception 'FAIL %: forbidden write succeeded',label;
end $$;
insert into auth.users(id) values
('00000000-0000-0000-0000-0000000000c1'),
('00000000-0000-0000-0000-0000000000c2');
insert into public.shops(id,owner_id,name,business_kind) values
('10000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000c1','Restaurant A','restaurant'),
('10000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-0000000000c2','Restaurant B','restaurant'),
('10000000-0000-0000-0000-0000000000c3','00000000-0000-0000-0000-0000000000c1','Salon A','salon');
select pg_temp.check(
 not has_table_privilege('anon','public.restaurant_tables','select')
 and not has_table_privilege('anon','public.restaurant_menu_items','select')
 and not has_table_privilege('anon','public.salon_booking_requests','select'),
 'public cannot read private shop tables'
);
select pg_temp.check(
 not has_function_privilege('anon','public.get_public_salon_booking(text)','execute')
 and not has_function_privilege('anon','public.request_salon_booking(text,text,text,text,timestamptz,uuid)','execute'),
 'public salon endpoint disabled until anti-abuse protection'
);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',true);
set local role authenticated;
insert into public.restaurant_tables(shop_id,label,capacity)
values('10000000-0000-0000-0000-0000000000c1','04',4);
insert into public.restaurant_menu_items(shop_id,name,category,kind,price_xaf,drink_stock)
values('10000000-0000-0000-0000-0000000000c1','Jus maison','Boissons','drink',1000,8);
insert into public.salon_services(shop_id,name,price_xaf,duration_minutes)
values('10000000-0000-0000-0000-0000000000c3','Tresses',10000,90);
select pg_temp.check(
 (select count(*) from public.restaurant_tables where shop_id='10000000-0000-0000-0000-0000000000c1')=1,
 'owner can see his table'
);
select pg_temp.expect_denied($$
 insert into public.restaurant_tables(shop_id,label,capacity)
 values('10000000-0000-0000-0000-0000000000c2','04',4)
$$, 'owner A cannot create table at restaurant B');
select pg_temp.expect_denied($$
 insert into public.restaurant_menu_items(shop_id,name,category,kind,price_xaf,drink_stock)
 values('10000000-0000-0000-0000-0000000000c3','Boisson','Boissons','drink',500,2)
$$, 'cannot create restaurant catalogue for salon');
select pg_temp.check(
 (select count(*) from public.restaurant_tables where shop_id='10000000-0000-0000-0000-0000000000c2')=0,
 'shop B has no exposed rows'
);
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c2',true);
set local role authenticated;
select pg_temp.check(
 (select count(*) from public.restaurant_tables)=0
 and (select count(*) from public.restaurant_menu_items)=0
 and (select count(*) from public.salon_services)=0,
 'owner B cannot view restaurant A or salon A data'
);
rollback;
