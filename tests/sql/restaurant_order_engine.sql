-- Restaurant order engine: complete life cycle on disposable test database, rolled back.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000d1'),
 ('00000000-0000-0000-0000-0000000000d2');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000000d1','Resto D','restaurant'),
 ('10000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-0000000000d2','Resto E','restaurant');
insert into public.restaurant_tables(id,shop_id,label,capacity) values
 ('20000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d1','04',4),
 ('20000000-0000-0000-0000-0000000000d2','10000000-0000-0000-0000-0000000000d2','04',4);
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock) values
 ('30000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d1','Poulet','Plats','dish',5000,null),
 ('30000000-0000-0000-0000-0000000000d2','10000000-0000-0000-0000-0000000000d1','Jus','Boissons','drink',1000,3),
 ('30000000-0000-0000-0000-0000000000d3','10000000-0000-0000-0000-0000000000d2','Jus concurrent','Boissons','drink',1500,5);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d1',true);
set local role authenticated;
do $check$
declare
 shop constant uuid := '10000000-0000-0000-0000-0000000000d1';
 t constant uuid := '20000000-0000-0000-0000-0000000000d1';
 dish constant uuid := '30000000-0000-0000-0000-0000000000d1';
 drink constant uuid := '30000000-0000-0000-0000-0000000000d2';
 other_drink constant uuid := '30000000-0000-0000-0000-0000000000d3';
 sess uuid; next_sess uuid; first_person uuid; second_person uuid;
 first_line uuid; second_line uuid; add_line uuid;
 ref text; result boolean; amt bigint; v integer;
begin
 sess:=public.restaurant_open_table(shop,t,2);
 if sess is null then raise exception 'No table session'; end if;
 begin
  perform public.restaurant_open_table(shop,t,4);
  raise exception 'Second group incorrectly opened the occupied table';
 exception when raise_exception then
  if sqlerrm not like '%Table occupied%' then raise; end if;
 end;
 first_person:=public.restaurant_add_participant(shop,sess);
 second_person:=public.restaurant_add_participant(shop,sess);
 first_line:=public.restaurant_choose_item(shop,sess,first_person,dish,1);
 second_line:=public.restaurant_choose_item(shop,sess,second_person,drink,1);
 if not public.restaurant_mark_ready(shop,sess,first_person) then
  raise exception 'First participant to finish should be the leader';
 end if;
 if public.restaurant_mark_ready(shop,sess,second_person) then
  raise exception 'Second finisher incorrectly became leader';
 end if;
 if not exists(select 1 from public.restaurant_participants where id=first_person and is_leader) then
  raise exception 'Leader not persisted';
 end if;
 begin
  perform public.restaurant_submit_group(shop,sess,second_person);
  raise exception 'Non leader incorrectly submitted';
 exception when raise_exception then
  if sqlerrm not like '%Only the group leader%' then raise; end if;
 end;
 -- Cross-shop item is never valid despite a valid UUID.
 begin
  perform public.restaurant_choose_item(shop,sess,first_person,other_drink,1);
  raise exception 'Other restaurant item accepted';
 exception when raise_exception then
  if sqlerrm not like '%Item unavailable%' then raise; end if;
 end;
 ref:=public.restaurant_submit_group(shop,sess,first_person);
 if ref<>'CMD-000001' then raise exception 'Incorrect first reference: %',ref; end if;
 select reserved_drink_stock,drink_stock into v,amt
  from public.restaurant_menu_items where id=drink;
 if v<>1 or amt<>3 then raise exception 'Drink reserved incorrectly'; end if;
 add_line:=public.restaurant_staff_add_item(shop,sess,drink,1);
 if (select reserved_drink_stock from public.restaurant_menu_items where id=drink)<>2 then
  raise exception 'Staff addition not reserved';
 end if;
 begin
  perform public.restaurant_staff_add_item(shop,sess,drink,2);
  raise exception 'Oversold drink stock';
 exception when raise_exception then
  if sqlerrm not like '%Drink out of stock%' then raise; end if;
 end;
 -- Cashier cannot free a table before every ordered item is served.
 begin
  perform public.restaurant_capture_cash(shop,sess,7000,'40000000-0000-0000-0000-0000000000d3');
  raise exception 'Unserved table incorrectly closed';
 exception when raise_exception then
  if sqlerrm not like '%Serve all ordered items%' then raise; end if;
 end;
 if exists(select 1 from public.restaurant_cash_payments where session_id=sess) then
   raise exception 'A rejected closing payment was incorrectly stored';
 end if;
 perform public.restaurant_mark_served(shop,first_line);
 perform public.restaurant_mark_served(shop,second_line);
 perform public.restaurant_mark_served(shop,second_line);
 perform public.restaurant_mark_served(shop,add_line);
 select drink_stock,reserved_drink_stock into v,amt
  from public.restaurant_menu_items where id=drink;
 if v<>1 or amt<>0 then raise exception 'Incorrect stock after service %/%',v,amt; end if;
 if (select count(*) from public.restaurant_drink_movements where shop_id=shop)<>2 then
  raise exception 'Service wrote duplicate drink movement';
 end if;
 -- No stock UPDATE directly from a browser, even for the owner.
 begin
  update public.restaurant_menu_items set drink_stock=999 where id=drink;
  raise exception 'Direct stock UPDATE unexpectedly succeeded';
 exception when insufficient_privilege then null;
 end;
 if public.restaurant_adjust_drink_stock(shop,drink,2,'Nouvel arrivage')<>3 then
   raise exception 'Audited delivery incorrect';
 end if;
 if (select count(*) from public.restaurant_drink_adjustments where shop_id=shop)<>1 then
   raise exception 'Missing stock adjustment audit';
 end if;
 begin
  perform public.restaurant_adjust_drink_stock(shop,drink,-4,'Erreur inventaire');
  raise exception 'Negative stock incorrectly accepted';
 exception when raise_exception then
  if sqlerrm not like '%Insufficient unreserved stock%' then raise; end if;
 end;
 if (select drink_stock from public.restaurant_menu_items where id=drink)<>3 then
   raise exception 'Failed adjustment changed stock';
 end if;
 if (select count(*) from public.restaurant_session_lines where session_id=sess)<>3 then
  raise exception 'Wrong number of order lines';
 end if;
 result:=public.restaurant_capture_cash(shop,sess,3000,'40000000-0000-0000-0000-0000000000d1');
 if result then raise exception 'Partial payment incorrectly released table'; end if;
 begin
  perform public.restaurant_open_table(shop,t,1);
  raise exception 'QR became free after partial payment';
 exception when raise_exception then
  if sqlerrm not like '%Table occupied%' then raise; end if;
 end;
 result:=public.restaurant_capture_cash(shop,sess,4000,'40000000-0000-0000-0000-0000000000d2');
 if not result then raise exception 'Full payment failed to close session'; end if;
 result:=public.restaurant_capture_cash(shop,sess,4000,'40000000-0000-0000-0000-0000000000d2');
 if not result or (select count(*) from public.restaurant_cash_payments where session_id=sess)<>2 then
  raise exception 'Idempotent payment repeated';
 end if;
 if (select status from public.restaurant_table_sessions where id=sess)<>'closed_paid' then
  raise exception 'Session not closed';
 end if;
 begin
  perform public.restaurant_staff_add_item(shop,sess,drink,1);
  raise exception 'Post-payment item incorrectly accepted';
 exception when raise_exception then
  if sqlerrm not like '%Table not taking additions%' then raise; end if;
 end;
 next_sess:=public.restaurant_open_table(shop,t,1);
 if next_sess=sess then raise exception 'Old session reused'; end if;
 if (select count(*) from public.restaurant_table_sessions where table_id=t)<>2 then
  raise exception 'Invalid session history';
 end if;
 if (select count(*) from public.restaurant_cash_payments where session_id=sess)<>2 then
  raise exception 'Cash accounting mismatch';
 end if;
end;
$check$;

-- RLS, functions and token secrecy: foreign shop cannot see the first restaurant.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d2',true);
select count(*)=0 as shop_d_secluded from public.restaurant_table_sessions
 where shop_id='10000000-0000-0000-0000-0000000000d1';
do $check$
begin
 begin
  perform public.restaurant_open_table(
   '10000000-0000-0000-0000-0000000000d1',
   '20000000-0000-0000-0000-0000000000d1',1);
  raise exception 'Foreign restaurant table opened';
 exception when insufficient_privilege then null;
 end;
end;$check$;

rollback;
