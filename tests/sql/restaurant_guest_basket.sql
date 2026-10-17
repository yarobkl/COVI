-- Full collaborative flow on disposable Postgres; never touches live COVI.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
('00000000-0000-0000-0000-0000000000a1'),
('00000000-0000-0000-0000-0000000000a2');
insert into public.shops(id,owner_id,name,business_kind) values
('10000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a1','Resto A','restaurant'),
('10000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000a2','Resto B','restaurant');
insert into public.restaurant_tables(id,shop_id,label,capacity,qr_token) values
('20000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-0000000000a1','04',4,repeat('a',64)),
('20000000-0000-0000-0000-0000000000a2','10000000-0000-0000-0000-0000000000a2','04',4,repeat('b',64));
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock) values
('30000000-0000-0000-0000-0000000000a1','10000000-0000-0000-0000-0000000000a1','Poisson','Plats','dish',6000,null),
('30000000-0000-0000-0000-0000000000a2','10000000-0000-0000-0000-0000000000a1','Eau','Boissons','drink',1000,5),
('30000000-0000-0000-0000-0000000000a3','10000000-0000-0000-0000-0000000000a2','Boisson du restaurant B','Boissons','drink',9999,4);
do $security$
begin
 if has_function_privilege('anon','public.restaurant_guest_join(text,text)','execute')
  or has_function_privilege('authenticated','public.restaurant_guest_join(text,text)','execute')
  or has_function_privilege('anon','public.restaurant_guest_submit(text,text)','execute')
  or has_function_privilege('authenticated','public.restaurant_guest_choose_item(text,text,uuid,integer)','execute')
  or has_function_privilege('service_role','public.restaurant_commit_group(uuid,uuid,uuid)','execute')
 then raise exception 'Guest RPC must not be exposed directly'; end if;
 if not has_function_privilege('service_role','public.restaurant_guest_join(text,text)','execute')
 then raise exception 'Server gateway cannot join'; end if;
end $security$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
set local role authenticated;
do $owner$
declare s uuid;c text;
begin
 s:=public.restaurant_open_table('10000000-0000-0000-0000-0000000000a1',
  '20000000-0000-0000-0000-0000000000a1',2);
 c:=public.restaurant_issue_group_code('10000000-0000-0000-0000-0000000000a1',s);
 if c !~ '^[A-F0-9]{8}$' then raise exception 'Invalid issued code'; end if;
 perform set_config('app.guest_test_code',c,true);
 perform set_config('app.guest_test_session',s::text,true);
end $owner$;
reset role;
set local role service_role;
do $guests$
declare r jsonb;secret1 text;secret2 text;c text;extra jsonb;
begin
 c:=current_setting('app.guest_test_code');
 begin
  perform public.restaurant_guest_join(repeat('a',64),'00000000');
  raise exception 'Wrong group code accepted';
 exception when raise_exception then
  if sqlerrm not like '%Invalid or expired group code%' then raise; end if;
 end;
 r:=public.restaurant_guest_join(repeat('a',64),c);
 secret1:=r->>'participantToken';
 if secret1 !~ '^[a-f0-9]{64}$' then raise exception 'Secret missing'; end if;
 perform set_config('app.guest_test_one',secret1,true);
 r:=public.restaurant_guest_join(repeat('a',64),c);
 secret2:=r->>'participantToken';
 perform set_config('app.guest_test_two',secret2,true);
 begin
  extra:=public.restaurant_guest_join(repeat('a',64),c);
  raise exception 'Third phone admitted to two-person group';
 exception when raise_exception then
  if sqlerrm not like '%participant limit%' then raise; end if;
 end;
 if (select p.participant_token from public.restaurant_participants p
 where p.id=(select id from public.restaurant_participants order by created_at,id limit 1))=secret1 then
  raise exception 'Guest bearer secret stored in clear'; end if;
 perform public.restaurant_guest_choose_item(
  repeat('a',64),secret1,'30000000-0000-0000-0000-0000000000a1',1);
 perform public.restaurant_guest_choose_item(
  repeat('a',64),secret2,'30000000-0000-0000-0000-0000000000a2',1);
 begin
  perform public.restaurant_guest_choose_item(
   repeat('a',64),secret1,'30000000-0000-0000-0000-0000000000a3',1);
  raise exception 'Other restaurant menu accepted';
 exception when raise_exception then
  if sqlerrm not like '%Item unavailable%' then raise; end if;
 end;
 begin
  perform public.restaurant_guest_choose_item(
   repeat('b',64),secret1,'30000000-0000-0000-0000-0000000000a1',1);
  raise exception 'Cross-restaurant QR accepted';
 exception when raise_exception then
  if sqlerrm not like '%expired%' then raise; end if;
 end;
 r:=public.restaurant_guest_mark_ready(repeat('a',64),secret1);
 if r->>'isLeader'<>'true' then raise exception 'First ready participant not leader'; end if;
 if (public.restaurant_guest_status(repeat('a',64),secret1))->>'ready'<>'true' then
  raise exception 'Group state not visible'; end if;
 begin
  perform public.restaurant_guest_submit(repeat('a',64),secret1);
  raise exception 'Premature group submission accepted';
 exception when raise_exception then
  if sqlerrm not like '%Waiting for participant choices%' then raise; end if;
 end;
 r:=public.restaurant_guest_mark_ready(repeat('a',64),secret2);
 if r->>'isLeader'='true' or r->>'readyParticipants'<>'2' then
   raise exception 'Second participant was incorrectly promoted'; end if;
 begin
  perform public.restaurant_guest_submit(repeat('a',64),secret2);
  raise exception 'Non leader submitted a group';
 exception when raise_exception then
  if sqlerrm not like '%Only the group leader%' then raise; end if;
 end;
 if public.restaurant_guest_submit(repeat('a',64),secret1)<>'CMD-000001' then
  raise exception 'Incorrect group reference'; end if;
 if public.restaurant_guest_submit(repeat('a',64),secret1)<>'CMD-000001' then
  raise exception 'Double click created new order'; end if;
 if (select count(*) from public.restaurant_table_sessions where shop_id='10000000-0000-0000-0000-0000000000a1')<>1
 then raise exception 'Second session created'; end if;
 if (select count(*) from public.restaurant_session_lines where
  session_id=current_setting('app.guest_test_session')::uuid and status='ordered')<>2 then
  raise exception 'Group lines not submitted'; end if;
 if (select reserved_drink_stock from public.restaurant_menu_items
  where id='30000000-0000-0000-0000-0000000000a2')<>1 then
  raise exception 'Drink not reserved'; end if;
end $guests$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
set local role authenticated;
do $cash$
declare s uuid;l record;paid boolean;
begin
 s:=current_setting('app.guest_test_session')::uuid;
 for l in select id from public.restaurant_session_lines where shop_id='10000000-0000-0000-0000-0000000000a1'
  and session_id=s loop
  perform public.restaurant_mark_served('10000000-0000-0000-0000-0000000000a1',l.id);
 end loop;
 paid:=public.restaurant_capture_cash('10000000-0000-0000-0000-0000000000a1',s,7000,
 '40000000-0000-0000-0000-0000000000a1');
 if not paid then raise exception 'Paid table not closed'; end if;
end $cash$;
reset role;
set local role service_role;
do $after$
declare c text;r jsonb;
begin
 c:=current_setting('app.guest_test_one');
 if public.restaurant_guest_status(repeat('a',64),c) is not null then
  raise exception 'Old guest token still accesses a closed session'; end if;
 begin
  perform public.restaurant_guest_choose_item(repeat('a',64),c,
  '30000000-0000-0000-0000-0000000000a1',1);
  raise exception 'Old guest token modified paid table';
 exception when raise_exception then
  if sqlerrm not like '%expired%' then raise; end if;
 end;
end $after$;
rollback;
