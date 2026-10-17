-- Restaurant staff: invitations, permission scoping and employment privacy.
-- Executed in the disposable CI database, rolled back afterwards.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000a1'),
 ('00000000-0000-0000-0000-0000000000a2'),
 ('00000000-0000-0000-0000-0000000000a3'),
 ('00000000-0000-0000-0000-0000000000a4');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000a1','00000000-0000-0000-0000-0000000000a1','Restau Personnel A','restaurant'),
 ('10000000-0000-0000-0000-0000000000a2','00000000-0000-0000-0000-0000000000a2','Restau Personnel B','restaurant');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
set local role authenticated;
do $owner$
declare v jsonb;c text;s uuid:='10000000-0000-0000-0000-0000000000a1';
begin
 v:=public.restaurant_staff_create_invite(s,'Serveuse Test','waiter');
 c:=v->>'code';
 if c !~ '^[A-F0-9]{32}$' then raise exception 'Invalid invite format'; end if;
 perform set_config('app.staff_waiter_code',c,true);
 v:=public.restaurant_staff_create_invite(s,'Caisse Test','cashier');
 perform set_config('app.staff_cashier_code',v->>'code',true);
 v:=public.restaurant_staff_create_invite(s,'Cuisine Test','kitchen');
 perform set_config('app.staff_kitchen_code',v->>'code',true);
 if (select count(*) from public.restaurant_staff_pending_invites(s))<>3 then
  raise exception 'Missing pending invitations';end if;
 begin
  perform public.restaurant_staff_create_invite('10000000-0000-0000-0000-0000000000a2','Étranger','cashier');
  raise exception 'Owner A created an invite for shop B';
 exception when insufficient_privilege then null;
 end;
end $owner$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a3',true);
set local role authenticated;
do $waiter$
declare v jsonb;
begin
 v:=public.restaurant_staff_join(current_setting('app.staff_waiter_code'));
 if v->>'ok'<>'true' then raise exception 'Cannot join the authorized restaurant';end if;
 if (select count(*) from public.restaurant_staff_my_spaces())<>1 then
  raise exception 'Staff work space missing';end if;
 if not public.restaurant_staff_allowed('10000000-0000-0000-0000-0000000000a1','staff_add_item')
   or not public.restaurant_staff_allowed('10000000-0000-0000-0000-0000000000a1','issue_group_code')
   or public.restaurant_staff_allowed('10000000-0000-0000-0000-0000000000a1','capture_cash')
   or public.restaurant_staff_allowed('10000000-0000-0000-0000-0000000000a1','unknown')
   or public.restaurant_staff_allowed('10000000-0000-0000-0000-0000000000a2','staff_add_item') then
  raise exception 'Waiter permissions/tenant invalid';end if;
 -- Each failure must be persisted, not rolled back after a raised SQL exception.
 if (public.restaurant_staff_join('00000000000000000000000000000000'))->>'ok'<>'false' then
  raise exception 'Bad code accepted';end if;
 if (select count(*) from public.restaurant_staff_invite_attempts where user_id=auth.uid() and not successful)<>1 then
  raise exception 'Failed attempt was not stored';end if;
 if (select count(*) from public.restaurant_staff_members)<>0 then
  -- Direct RLS table read is owner-only, even for the staff member.
  raise exception 'Staff can read member identities without owner permission';end if;
 if (select count(*) from public.restaurant_staff_events)<>0 then
  raise exception 'Staff can read owner audit events';end if;
end $waiter$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a4',true);
set local role authenticated;
do $cashier$
declare v jsonb;
begin
 v:=public.restaurant_staff_join(current_setting('app.staff_cashier_code'));
 if v->>'staffRole'<>'cashier' then raise exception 'Incorrect cashier role'; end if;
 if not public.restaurant_staff_allowed('10000000-0000-0000-0000-0000000000a1','capture_cash')
   or public.restaurant_staff_allowed('10000000-0000-0000-0000-0000000000a1','staff_add_item')
   or public.restaurant_staff_allowed('10000000-0000-0000-0000-0000000000a1','mark_served') then
  raise exception 'Cashier permissions invalid'; end if;
end $cashier$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a2',true);
set local role authenticated;
do $other$
begin
 if (select count(*) from public.restaurant_staff_members)<>0
    or (select count(*) from public.restaurant_staff_events)<>0 then
  raise exception 'Shop B may not see shop A people or audit';end if;
 begin
  perform public.restaurant_staff_disable('10000000-0000-0000-0000-0000000000a1',
    (select id from public.restaurant_staff_members limit 1));
  raise exception 'Foreign manager disabled shop A staff';
 exception when insufficient_privilege then null;
 end;
end $other$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a1',true);
set local role authenticated;
do $disable$
declare v_id uuid;
begin
 select id into v_id from public.restaurant_staff_members
 where shop_id='10000000-0000-0000-0000-0000000000a1'
 and user_id='00000000-0000-0000-0000-0000000000a3';
 if not public.restaurant_staff_disable(
   '10000000-0000-0000-0000-0000000000a1',v_id) then raise exception 'Disable failed';end if;
 if (select count(*) from public.restaurant_staff_events where event_type='member_disabled')<>1 then
  raise exception 'Missing owner audit';end if;
end $disable$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000a3',true);
set local role authenticated;
do $revoked$
begin
 if public.restaurant_staff_allowed('10000000-0000-0000-0000-0000000000a1','staff_add_item')
  or (select count(*) from public.restaurant_staff_my_spaces())<>0 then
  raise exception 'Disabled staff still has permissions';end if;
end $revoked$;
rollback;
