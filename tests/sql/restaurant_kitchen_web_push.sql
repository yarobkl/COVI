-- Push subscriptions and server dispatch, isolated PostgreSQL transaction.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000b1'),
 ('00000000-0000-0000-0000-0000000000b2'),
 ('00000000-0000-0000-0000-0000000000b3'),
 ('00000000-0000-0000-0000-0000000000b4');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b1','Push Cuisine A','restaurant'),
 ('10000000-0000-0000-0000-0000000000b4','00000000-0000-0000-0000-0000000000b4','Push Cuisine B','restaurant');
insert into public.restaurant_staff_members(shop_id,user_id,display_name,staff_role,created_by)
values
 ('10000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b2','Cuisinier B2','kitchen','00000000-0000-0000-0000-0000000000b1'),
 ('10000000-0000-0000-0000-0000000000b1','00000000-0000-0000-0000-0000000000b3','Serveur B3','waiter','00000000-0000-0000-0000-0000000000b1');
insert into public.restaurant_tables(id,shop_id,label,capacity) values
 ('20000000-0000-0000-0000-0000000000b1','10000000-0000-0000-0000-0000000000b1','04',4);
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock) values
 ('30000000-0000-0000-0000-0000000000b1','10000000-0000-0000-0000-0000000000b1','Poisson','Plats','dish',4500,null);
do $hosts$
begin
 if not public.restaurant_push_endpoint_allowed(
  'https://fcm.googleapis.com/fcm/send/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  or public.restaurant_push_endpoint_allowed('https://127.0.0.1/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  or public.restaurant_push_endpoint_allowed('https://fcm.googleapis.com.attacker.com/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
  or public.restaurant_push_endpoint_allowed('http://fcm.googleapis.com/fcm/send/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
 then raise exception 'SSRF host list defective';end if;
 if has_function_privilege('anon','public.restaurant_kitchen_push_register(uuid,text,text,text)','execute')
  or has_function_privilege('authenticated','public.restaurant_kitchen_push_claim(integer)','execute')
  or has_function_privilege('authenticated','public.restaurant_kitchen_push_finish(uuid,uuid,text,text)','execute')
 then raise exception 'Push endpoint grants unsafe';end if;
end $hosts$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',true);
set local role authenticated;
do $cook_register$
declare sh uuid:='10000000-0000-0000-0000-0000000000b1';
endpoint text:='https://fcm.googleapis.com/fcm/send/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
begin
 if not public.restaurant_kitchen_push_register(sh,endpoint,repeat('A',87),repeat('B',22))
 then raise exception 'Authorized kitchen cannot register device';end if;
 begin
  perform (select count(*) from public.restaurant_kitchen_push_subscriptions);
  raise exception 'Kitchen could read secret subscription keys';
 exception when insufficient_privilege then null;end;
 begin
  perform public.restaurant_kitchen_push_register(
   '10000000-0000-0000-0000-0000000000b4',endpoint,repeat('A',87),repeat('B',22));
  raise exception 'Staff subscribed to another shop';
 exception when insufficient_privilege then null;end;
end $cook_register$;
reset role;
-- Shared browser endpoint: changing to another restaurant must never leave
-- two active subscribers (and cross-shop alerts) on a single device.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b4',true);
set local role authenticated;
do $switch_device$
begin
 if not public.restaurant_kitchen_push_register(
   '10000000-0000-0000-0000-0000000000b4',
   'https://fcm.googleapis.com/fcm/send/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
   repeat('C',87),repeat('D',22))
 then raise exception 'New restaurant owner could not take over same browser endpoint';end if;
end $switch_device$;
reset role;
do $unique_device$
begin
 if (select count(*) from public.restaurant_kitchen_push_subscriptions)<>1
 or (select shop_id from public.restaurant_kitchen_push_subscriptions limit 1)
   <> '10000000-0000-0000-0000-0000000000b4'::uuid
 then raise exception 'Same browser endpoint delivers to multiple restaurants';end if;
end $unique_device$;
-- Returning to the first restaurant must re-bind this endpoint and its event cursor.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',true);
set local role authenticated;
do $restore_device$
begin
 if not public.restaurant_kitchen_push_register(
   '10000000-0000-0000-0000-0000000000b1',
   'https://fcm.googleapis.com/fcm/send/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
   repeat('A',87),repeat('B',22))
 then raise exception 'Kitchen staff could not reclaim browser endpoint';end if;
end $restore_device$;
reset role;
do $restored_device$
begin
 if (select count(*) from public.restaurant_kitchen_push_subscriptions)<>1
 or (select shop_id from public.restaurant_kitchen_push_subscriptions limit 1)
   <> '10000000-0000-0000-0000-0000000000b1'::uuid
 then raise exception 'Device ownership was not restored';end if;
end $restored_device$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b3',true);
set local role authenticated;
do $waiter$
begin
 begin
  perform public.restaurant_kitchen_push_register(
   '10000000-0000-0000-0000-0000000000b1',
   'https://fcm.googleapis.com/fcm/send/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
   repeat('A',87),repeat('B',22));
  raise exception 'Waiter subscribed to kitchen';
 exception when insufficient_privilege then null;end;
end $waiter$;
reset role;
-- Unauthorized callers cannot claim jobs, even using guessed SQL names.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
select set_config('request.jwt.claim.role','authenticated',true);
set local role authenticated;
do $roles$
begin
 begin
  perform public.restaurant_kitchen_push_claim(25);
  raise exception 'Non-service role claimed push jobs';
 exception when insufficient_privilege then null;end;
end $roles$;
reset role;
set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
do $before$
begin
 if jsonb_array_length(public.restaurant_kitchen_push_claim(25))<>0 then
  raise exception 'Kitchen push created for no order';end if;
end $before$;
reset role;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
set local role authenticated;
do $order$
declare sh uuid:='10000000-0000-0000-0000-0000000000b1';ss uuid;member uuid;
begin
 ss:=public.restaurant_open_table(sh,'20000000-0000-0000-0000-0000000000b1',2);
 member:=public.restaurant_add_participant(sh,ss);
 perform public.restaurant_choose_item(sh,ss,member,'30000000-0000-0000-0000-0000000000b1',1);
 perform public.restaurant_mark_ready(sh,ss,member);
 perform public.restaurant_submit_group(sh,ss,member);
end $order$;
reset role;
set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
do $dispatch$
declare jobs jsonb;item jsonb;result boolean;sh uuid:='10000000-0000-0000-0000-0000000000b1';
begin
 jobs:=public.restaurant_kitchen_push_claim(25);
 if jsonb_array_length(jobs)<>1 then raise exception 'No push queued to subscribed chef';end if;
 item:=jobs->0;
 if item->>'count'<>'1' or item->>'through' is null
  or item->>'endpoint' not like 'https://fcm.googleapis.com/%'
 then raise exception 'Push job data or exact event cursor missing';end if;
 if jsonb_array_length(public.restaurant_kitchen_push_claim(25))<>0
 then raise exception 'Same leased notification could be dispatched concurrently';end if;
 result:=public.restaurant_kitchen_push_finish(
  (item->>'id')::uuid,(item->>'lease')::uuid,item->>'through','retry');
 if not result then raise exception 'Retry not acknowledged';end if;
 if jsonb_array_length(public.restaurant_kitchen_push_claim(25))<>0
 then raise exception 'Retry executed before cooldown';end if;
 update public.restaurant_kitchen_push_subscriptions
 set next_retry_at=now()-interval '1 minute' where shop_id=sh;
 jobs:=public.restaurant_kitchen_push_claim(25);item:=jobs->0;
 if jsonb_array_length(jobs)<>1 then raise exception 'Failed notification lost instead of retried';end if;
 result:=public.restaurant_kitchen_push_finish(
  (item->>'id')::uuid,(item->>'lease')::uuid,item->>'through','sent');
 if not result then raise exception 'Sent acknowledgement missing';end if;
 if jsonb_array_length(public.restaurant_kitchen_push_claim(25))<>0
 then raise exception 'Already sent event delivered again';end if;
 if (select last_delivered_event_id from public.restaurant_kitchen_push_subscriptions where shop_id=sh)<>(item->>'through')::bigint
 then raise exception 'Sent cursor not persisted';end if;
end $dispatch$;
reset role;
-- The kitchen staffer can unsubscribe only their own browser and reconnect
-- without re-delivery of already acknowledged events.
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',true);
set local role authenticated;
do $opt_out_and_reconnect$
declare sh uuid:='10000000-0000-0000-0000-0000000000b1';
endpoint text:='https://fcm.googleapis.com/fcm/send/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
begin
 if not public.restaurant_kitchen_push_unregister(sh,endpoint)
 then raise exception 'Authenticated chef could not opt out';end if;
 if public.restaurant_kitchen_push_unregister(sh,endpoint)
 then raise exception 'Unregister falsely claims to remove the same endpoint twice';end if;
 if not public.restaurant_kitchen_push_register(sh,endpoint,repeat('A',87),repeat('B',22))
 then raise exception 'Chef could not reconnect their browser';end if;
end $opt_out_and_reconnect$;
reset role;
set local role service_role;
select set_config('request.jwt.claim.role','service_role',true);
do $no_duplicate_on_reconnect$
begin
 if jsonb_array_length(public.restaurant_kitchen_push_claim(25))<>0
 then raise exception 'Reconnecting replayed an already delivered preparation';end if;
end $no_duplicate_on_reconnect$;
reset role;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',true);
set local role authenticated;
do $revoke$
declare mid uuid;
begin
 select id into mid from public.restaurant_staff_members where staff_role='kitchen';
 if not public.restaurant_staff_disable('10000000-0000-0000-0000-0000000000b1',mid)
 then raise exception 'Cannot revoke kitchen staff';end if;
end $revoke$;
reset role;
do $check_revocation$
begin
 if (select count(*) from public.restaurant_kitchen_push_subscriptions)>0
 then raise exception 'Revoked chef still has a remote push endpoint';end if;
end $check_revocation$;
rollback;
