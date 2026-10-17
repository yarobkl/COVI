-- Restaurant employee end-to-end authorization: isolated test database, rollback.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000b1'),
 ('00000000-0000-0000-0000-0000000000b2'),
 ('00000000-0000-0000-0000-0000000000b3'),
 ('00000000-0000-0000-0000-0000000000b4'),
 ('00000000-0000-0000-0000-0000000000b5');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b1','Resto B1','restaurant'),
 ('10000000-0000-0000-0000-0000000000b5','00000000-0000-0000-0000-0000000000b5','Resto B5','restaurant');
insert into public.restaurant_tables(id,shop_id,label,capacity) values
 ('20000000-0000-0000-0000-0000000000b1','10000000-0000-0000-0000-0000000000b1','04',4);
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock) values
 ('30000000-0000-0000-0000-0000000000b1','10000000-0000-0000-0000-0000000000b1','Poisson','Plats','dish',6000,null),
 ('30000000-0000-0000-0000-0000000000b2','10000000-0000-0000-0000-0000000000b1','Eau','Boissons','drink',1000,4);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
set local role authenticated;
do $invite$
declare p uuid:='10000000-0000-0000-0000-0000000000b1';v jsonb;
begin
 v:=public.restaurant_staff_create_invite(p,'Serveuse B2','waiter');
 perform set_config('app.staff_b2',v->>'code',true);
 v:=public.restaurant_staff_create_invite(p,'Cuisine B3','kitchen');
 perform set_config('app.staff_b3',v->>'code',true);
 v:=public.restaurant_staff_create_invite(p,'Caisse B4','cashier');
 perform set_config('app.staff_b4',v->>'code',true);
end $invite$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',true);
set local role authenticated;
do $serveuse$
declare p uuid:='10000000-0000-0000-0000-0000000000b1';s uuid;v jsonb;
begin
 v:=public.restaurant_staff_join(current_setting('app.staff_b2'));
 if v->>'ok'<>'true' then raise exception 'Waiter join failed'; end if;
 s:=public.restaurant_open_table(p,'20000000-0000-0000-0000-0000000000b1',2);
 perform set_config('app.test_service_session',s::text,true);
 if public.restaurant_issue_group_code(p,s) !~ '^[A-F0-9]{8}$' then
  raise exception 'Waiter cannot issue group code'; end if;
 if public.restaurant_staff_room(p)->>'role'<>'waiter' then
  raise exception 'Wrong waiter room'; end if;
 begin
  perform public.restaurant_capture_cash(p,s,6000,'40000000-0000-0000-0000-0000000000b2');
  raise exception 'Waiter can collect cash';
 exception when insufficient_privilege then null;
 end;
end $serveuse$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
set local role authenticated;
do $owner$
declare p uuid:='10000000-0000-0000-0000-0000000000b1';
 s uuid:=current_setting('app.test_service_session')::uuid;u uuid;l uuid;
begin
 u:=public.restaurant_add_participant(p,s);
 l:=public.restaurant_choose_item(p,s,u,'30000000-0000-0000-0000-0000000000b1',1);
 perform set_config('app.staff_test_dish',l::text,true);
 if not public.restaurant_mark_ready(p,s,u) then raise exception 'Leader not assigned';end if;
 if public.restaurant_submit_group(p,s,u)<>'CMD-000001' then raise exception 'Order not sent'; end if;
end $owner$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',true);
set local role authenticated;
do $serveuse$
declare p uuid:='10000000-0000-0000-0000-0000000000b1';v uuid;
begin
 v:=public.restaurant_staff_add_item(p,current_setting('app.test_service_session')::uuid,
  '30000000-0000-0000-0000-0000000000b2',1);
 perform set_config('app.staff_test_drink',v::text,true);
end $serveuse$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b3',true);
set local role authenticated;
do $cuisine$
declare p uuid:='10000000-0000-0000-0000-0000000000b1';v jsonb;room jsonb;
begin
 v:=public.restaurant_staff_join(current_setting('app.staff_b3'));
 if v->>'ok'<>'true' then raise exception 'Kitchen join failed';end if;
 room:=public.restaurant_staff_room(p);
 if room->>'role'<>'kitchen'
    or room->'payments'<>'[]'::jsonb
    or exists(select 1 from jsonb_array_elements(room->'lines') x where x->'unitPriceXaf'<>'null'::jsonb)
 then raise exception 'Kitchen received private cash totals';end if;
 perform public.restaurant_mark_served(p,current_setting('app.staff_test_dish')::uuid);
 perform public.restaurant_mark_served(p,current_setting('app.staff_test_drink')::uuid);
 begin
  perform public.restaurant_staff_add_item(p,current_setting('app.test_service_session')::uuid,
    '30000000-0000-0000-0000-0000000000b2',1);
  raise exception 'Kitchen added extra drink';
 exception when insufficient_privilege then null;
 end;
 begin
  perform public.restaurant_capture_cash(p,current_setting('app.test_service_session')::uuid,
    7000,'40000000-0000-0000-0000-0000000000b3');
  raise exception 'Kitchen collected cash';
 exception when insufficient_privilege then null;
 end;
end $cuisine$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b4',true);
set local role authenticated;
do $caisse$
declare p uuid:='10000000-0000-0000-0000-0000000000b1';v jsonb;
 s uuid:=current_setting('app.test_service_session')::uuid;is_paid boolean;
begin
 v:=public.restaurant_staff_join(current_setting('app.staff_b4'));
 if v->>'ok'<>'true' then raise exception 'Cashier join failed'; end if;
 if public.restaurant_staff_room(p)->>'role'<>'cashier' then
  raise exception 'Wrong cashier view'; end if;
 begin
  perform public.restaurant_mark_served(p,current_setting('app.staff_test_dish')::uuid);
  raise exception 'Cashier served food';
 exception when insufficient_privilege then null;
 end;
 is_paid:=public.restaurant_capture_cash(p,s,7000,'40000000-0000-0000-0000-0000000000b4');
 if not is_paid then raise exception 'Cashier failed to settle bill';end if;
 if not public.restaurant_capture_cash(p,s,7000,'40000000-0000-0000-0000-0000000000b4') then
  raise exception 'Cash payment lost idempotence';end if;
end $caisse$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
set local role authenticated;
do $audit$
declare p uuid:='10000000-0000-0000-0000-0000000000b1';
begin
 if (select count(*) from public.restaurant_staff_events
  where shop_id=p and event_type='line_added'
    and actor_user_id='00000000-0000-0000-0000-0000000000b2')<>1 then
  raise exception 'Waiter addition audit missing';end if;
 if (select count(*) from public.restaurant_staff_events where shop_id=p
    and event_type='line_served'
    and actor_user_id='00000000-0000-0000-0000-0000000000b3')<>2 then
  raise exception 'Kitchen audit missing';end if;
 if (select count(*) from public.restaurant_staff_events where shop_id=p
  and event_type='payment_confirmed'
  and actor_user_id='00000000-0000-0000-0000-0000000000b4')<>1 then
  raise exception 'Cashier audit duplicated or missing';end if;
 if (select status from public.restaurant_table_sessions
 where id=current_setting('app.test_service_session')::uuid)<>'closed_paid' then
  raise exception 'Table remained locked after paid';end if;
end $audit$;
rollback;
