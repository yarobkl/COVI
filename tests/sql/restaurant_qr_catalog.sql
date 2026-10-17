-- QR table projection — isolated database; no application user can call the RPC.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000f1'),
 ('00000000-0000-0000-0000-0000000000f2');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000f1','Restaurant du fleuve','restaurant'),
 ('10000000-0000-0000-0000-0000000000f2','00000000-0000-0000-0000-0000000000f2','Restaurant du nord','restaurant');
insert into public.restaurant_tables(id,shop_id,label,capacity,qr_token) values
 ('20000000-0000-0000-0000-0000000000f1','10000000-0000-0000-0000-0000000000f1','04',4,repeat('a',64)),
 ('20000000-0000-0000-0000-0000000000f2','10000000-0000-0000-0000-0000000000f2','04',4,repeat('b',64));
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock,available)
values
 ('30000000-0000-0000-0000-0000000000f1','10000000-0000-0000-0000-0000000000f1','Poisson','Plats','dish',6000,null,true),
 ('30000000-0000-0000-0000-0000000000f2','10000000-0000-0000-0000-0000000000f1','Secret','Plats','dish',2000,null,false),
 ('30000000-0000-0000-0000-0000000000f3','10000000-0000-0000-0000-0000000000f2','Poulet du nord','Plats','dish',9000,null,true);
do $preflight$
begin
 if has_function_privilege('anon','public.restaurant_qr_catalog(text)','execute')
  or has_function_privilege('authenticated','public.restaurant_qr_catalog(text)','execute') then
  raise exception 'QR read RPC must be server-only';
 end if;
 if not has_function_privilege('service_role','public.restaurant_qr_catalog(text)','execute') then
  raise exception 'Service gateway lost QR lookup privilege';
 end if;
end $preflight$;
set local role service_role;
do $check$
declare d jsonb;
begin
 d:=public.restaurant_qr_catalog(repeat('a',64));
 if d->>'restaurantName'<>'Restaurant du fleuve'
    or d->>'tableName'<>'04' or (d->>'capacity')::int<>4
    or d->>'tableState'<>'free' then
  raise exception 'Wrong restaurant or table';
 end if;
 if jsonb_array_length(d->'menu')<>1 or d->'menu'->0->>'name'<>'Poisson'
    or d ? 'shop_id' or d ? 'qr_token' then
  raise exception 'Private or cross-shop data leaked to menu';
 end if;
 if public.restaurant_qr_catalog(repeat('b',64))->>'restaurantName'<>'Restaurant du nord' then
  raise exception 'Restaurant B wrong';
 end if;
 if public.restaurant_qr_catalog('bad') is not null then
  raise exception 'Invalid QR accepted';
 end if;
end $check$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000f1',true);
set local role authenticated;
do $owner$
declare ss uuid; pp uuid; li uuid; ref text; paid boolean;
begin
 ss:=public.restaurant_open_table(
  '10000000-0000-0000-0000-0000000000f1',
  '20000000-0000-0000-0000-0000000000f1',2);
 perform set_config('app.qr_test_session',ss::text,true);
end $owner$;
reset role;
set local role service_role;
do $check$
declare d jsonb;
begin
 d:=public.restaurant_qr_catalog(repeat('a',64));
 if d->>'tableState'<>'collecting' then raise exception 'Open group not visible'; end if;
 if d->>'tableName'<>'04' then raise exception 'QR table replaced'; end if;
end $check$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000f1',true);
set local role authenticated;
do $owner$
declare ss uuid; pp uuid; li uuid; ref text; paid boolean;
begin
 ss:=current_setting('app.qr_test_session')::uuid;
 pp:=public.restaurant_add_participant('10000000-0000-0000-0000-0000000000f1',ss);
 li:=public.restaurant_choose_item('10000000-0000-0000-0000-0000000000f1',
  ss,pp,'30000000-0000-0000-0000-0000000000f1',1);
 if not public.restaurant_mark_ready('10000000-0000-0000-0000-0000000000f1',ss,pp) then
  raise exception 'Leader not assigned'; end if;
 ref:=public.restaurant_submit_group('10000000-0000-0000-0000-0000000000f1',ss,pp);
 if ref<>'CMD-000001' then raise exception 'Wrong reference'; end if;
 perform public.restaurant_mark_served('10000000-0000-0000-0000-0000000000f1',li);
end $owner$;
reset role;
set local role service_role;
do $check$
begin
 if public.restaurant_qr_catalog(repeat('a',64))->>'tableState'<>'occupied' then
  raise exception 'Submitted session not marked occupied'; end if;
end $check$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000f1',true);
set local role authenticated;
do $owner$
declare ss uuid;
begin
 ss:=current_setting('app.qr_test_session')::uuid;
 if not public.restaurant_capture_cash('10000000-0000-0000-0000-0000000000f1',
   ss,6000,'40000000-0000-0000-0000-0000000000f1') then
   raise exception 'Paid table not closed';
 end if;
end $owner$;
reset role;
set local role service_role;
do $check$
begin
 if public.restaurant_qr_catalog(repeat('a',64))->>'tableState'<>'free' then
  raise exception 'QR did not unlock automatically after paid';
 end if;
end $check$;
rollback;
