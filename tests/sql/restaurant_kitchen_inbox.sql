-- Kitchen durable notification queue: tenant isolation, status, reconnect and ack.
-- On disposable CI database only.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000c1'),
 ('00000000-0000-0000-0000-0000000000c2'),
 ('00000000-0000-0000-0000-0000000000c3'),
 ('00000000-0000-0000-0000-0000000000c4');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000c1','Cuisine A','restaurant'),
 ('10000000-0000-0000-0000-0000000000c4','00000000-0000-0000-0000-0000000000c4','Cuisine B','restaurant');
insert into public.restaurant_staff_members(shop_id,user_id,display_name,staff_role,created_by)
 values
 ('10000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000c2','Cuisinier A','kitchen','00000000-0000-0000-0000-0000000000c1'),
 ('10000000-0000-0000-0000-0000000000c1','00000000-0000-0000-0000-0000000000c3','Serveuse A','waiter','00000000-0000-0000-0000-0000000000c1');
insert into public.restaurant_tables(id,shop_id,label,capacity) values
 ('20000000-0000-0000-0000-0000000000c1','10000000-0000-0000-0000-0000000000c1','T-4',4);
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock) values
 ('30000000-0000-0000-0000-0000000000c1','10000000-0000-0000-0000-0000000000c1','Poulet','Plat','dish',6500,null),
 ('30000000-0000-0000-0000-0000000000c2','10000000-0000-0000-0000-0000000000c1','Eau','Boissons','drink',1000,8);
do $secure$
begin
 if has_function_privilege('anon','public.restaurant_kitchen_inbox(uuid)','execute')
 or has_function_privilege('anon','public.restaurant_kitchen_acknowledge(uuid,text)','execute')
 then raise exception 'Anonymous visitor can access kitchen inbox';end if;
end $secure$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',true);
set local role authenticated;
do $owner$
declare sh uuid:='10000000-0000-0000-0000-0000000000c1';
sess uuid;person uuid;line uuid;empty jsonb;
begin
 sess:=public.restaurant_open_table(sh,'20000000-0000-0000-0000-0000000000c1',2);
 person:=public.restaurant_add_participant(sh,sess);
 line:=public.restaurant_choose_item(sh,sess,person,'30000000-0000-0000-0000-0000000000c1',1);
 empty:=public.restaurant_kitchen_inbox(sh);
 if jsonb_array_length(empty->'events')<>0 then
  raise exception 'Draft item alerted before sending group';end if;
 perform public.restaurant_mark_ready(sh,sess,person);
 perform public.restaurant_submit_group(sh,sess,person);
 perform set_config('app.kitchen_line',line::text,true);
 perform set_config('app.kitchen_session',sess::text,true);
end $owner$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c2',true);
set local role authenticated;
do $cook$
declare sh uuid:='10000000-0000-0000-0000-0000000000c1';
inbox jsonb;signal text;empty jsonb;
begin
 inbox:=public.restaurant_kitchen_inbox(sh);
 if jsonb_array_length(inbox->'events')<>1
  or inbox->'events'->0->>'item'<>'Poulet'
  or inbox->'events'->0->>'table'<>'T-4'
  or inbox->'events'->0 ? 'unitPriceXaf'
  or inbox->'events'->0 ? 'participantToken'
 then raise exception 'Kitchen feed missing item or revealing private information';end if;
 signal:=inbox->'events'->0->>'id';
 if public.restaurant_kitchen_acknowledge(sh,signal)<>signal
 then raise exception 'First acknowledgement failed';end if;
 if jsonb_array_length((public.restaurant_kitchen_inbox(sh))->'events')<>0
 then raise exception 'Acknowledged dish is still unread';end if;
 if public.restaurant_kitchen_acknowledge(sh,signal)<>signal then
  raise exception 'Duplicate acknowledgement moved cursor';end if;
 begin
  perform public.restaurant_kitchen_acknowledge(sh,'999999999');
  raise exception 'Fictitious future kitchen event acknowledged';
 exception when raise_exception then
  if sqlerrm not like '%does not belong%' then raise;end if;end;
 begin
  perform public.restaurant_kitchen_inbox('10000000-0000-0000-0000-0000000000c4');
  raise exception 'Kitchen A read restaurant B';
 exception when insufficient_privilege then null;end;
end $cook$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c3',true);
set local role authenticated;
do $waiter$
declare sh uuid:='10000000-0000-0000-0000-0000000000c1';
 line uuid;
begin
 begin
  perform public.restaurant_kitchen_inbox(sh);
  raise exception 'Waiter read confidential kitchen inbox';
 exception when insufficient_privilege then null;end;
 line:=public.restaurant_staff_add_item(sh,current_setting('app.kitchen_session')::uuid,
   '30000000-0000-0000-0000-0000000000c2',2);
 perform set_config('app.kitchen_drink_line',line::text,true);
end $waiter$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c2',true);
set local role authenticated;
do $cook2$
declare sh uuid:='10000000-0000-0000-0000-0000000000c1';first jsonb;
begin
 first:=public.restaurant_kitchen_inbox(sh);
 if jsonb_array_length(first->'events')<>1 or first->'events'->0->>'item'<>'Eau'
 then raise exception 'Waiter addition not delivered as kitchen event';end if;
 -- The unread event is preserved over a reconnect (no receipt yet).
 if (public.restaurant_kitchen_inbox(sh))->'events'<>first->'events'
 then raise exception 'Reconnect lost outstanding kitchen notification';end if;
 perform public.restaurant_mark_served(sh,current_setting('app.kitchen_drink_line')::uuid);
 if jsonb_array_length((public.restaurant_kitchen_inbox(sh))->'events')<>0
 then raise exception 'Already served drink produced a stale alert';end if;
end $cook2$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c4',true);
set local role authenticated;
do $other$
begin
 begin
  perform (select count(*) from public.restaurant_kitchen_events);
  raise exception 'Other owner read direct kitchen event table';
 exception when insufficient_privilege then null;end;
 begin
  perform public.restaurant_kitchen_acknowledge(
    '10000000-0000-0000-0000-0000000000c1','1');
  raise exception 'Other restaurant can acknowledge a kitchen event';
 exception when insufficient_privilege then null;end;
end $other$;
rollback;
