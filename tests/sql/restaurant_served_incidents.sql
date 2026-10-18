-- Restaurant served incident / no fabricated refund tests, isolated transaction.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000e1'),
 ('00000000-0000-0000-0000-0000000000e2'),
 ('00000000-0000-0000-0000-0000000000e3');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e1','Resto Incidents A','restaurant'),
 ('10000000-0000-0000-0000-0000000000e3','00000000-0000-0000-0000-0000000000e3','Resto Incidents B','restaurant');
insert into public.restaurant_tables(id,shop_id,label,capacity) values
 ('20000000-0000-0000-0000-0000000000e1','10000000-0000-0000-0000-0000000000e1','1',2);
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock) values
 ('30000000-0000-0000-0000-0000000000e1','10000000-0000-0000-0000-0000000000e1','Jus','Boisson','drink',1500,5);
insert into public.restaurant_staff_members(shop_id,user_id,display_name,staff_role,created_by)
values ('10000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e2',
 'Serveuse E2','waiter','00000000-0000-0000-0000-0000000000e1');
do $grants$
begin
 if has_function_privilege('anon','public.restaurant_report_served_issue(uuid,uuid,text,uuid)','execute')
 then raise exception 'Guest can report and cause privileged audit write';end if;
end $grants$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',true);
set local role authenticated;
do $start$
declare shop uuid:='10000000-0000-0000-0000-0000000000e1';
 sess uuid;person uuid;line uuid;
begin
 sess:=public.restaurant_open_table(shop,'20000000-0000-0000-0000-0000000000e1',1);
 person:=public.restaurant_add_participant(shop,sess);
 line:=public.restaurant_choose_item(shop,sess,person,'30000000-0000-0000-0000-0000000000e1',2);
 perform set_config('app.incident_session',sess::text,true);
 perform set_config('app.incident_line',line::text,true);
 perform public.restaurant_mark_ready(shop,sess,person);
 perform public.restaurant_submit_group(shop,sess,person);
end $start$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e2',true);
set local role authenticated;
do $waiter$
declare shop uuid:='10000000-0000-0000-0000-0000000000e1';
 line uuid:=current_setting('app.incident_line')::uuid;
 op uuid:='40000000-0000-0000-0000-0000000000e1';r jsonb;
begin
 begin
  perform public.restaurant_report_served_issue(shop,line,'Boisson déjà servie, mais mauvaise température',op);
  raise exception 'Unserved line incident allowed';
 exception when raise_exception then
  if sqlerrm not like '%Only served%' then raise;end if;
 end;
 perform public.restaurant_mark_served(shop,line);
 r:=public.restaurant_report_served_issue(shop,line,
  'Boisson déjà servie, mais mauvaise température',op);
 if r->>'state'<>'open' then raise exception 'Incident not opened';end if;
 perform set_config('app.incident_ticket',r->>'ticketId',true);
 if public.restaurant_report_served_issue(shop,line,
   'Boisson déjà servie, mais mauvaise température',op)->>'ticketId'<>r->>'ticketId'
 then raise exception 'Retry created another incident';end if;
 begin
  perform public.restaurant_report_served_issue(shop,line,'Autre description pour même opération',op);
  raise exception 'Changed operation id accepted';
 exception when raise_exception then
  if sqlerrm not like '%Operation key mismatch%' then raise;end if;end;
 if (select count(*) from public.restaurant_served_incidents)>0 then
  raise exception 'Waiter may read confidential incident queue';end if;
 begin
  perform public.restaurant_review_served_issue(shop,(r->>'ticketId')::uuid,
   'requires_refund_review','Client souhaite un geste commercial');
  raise exception 'Waiter may approve incident';
 exception when insufficient_privilege then null;end;
end $waiter$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e3',true);
set local role authenticated;
do $foreign$
begin
 if (select count(*) from public.restaurant_served_incidents)<>0 then
  raise exception 'Foreign owner can see other shop incidents';end if;
 begin
  perform public.restaurant_review_served_issue('10000000-0000-0000-0000-0000000000e1',
   current_setting('app.incident_ticket')::uuid,
   'reviewed','Propriétaire étranger refusé');
  raise exception 'Other owner reviewed incident';
 exception when insufficient_privilege then null;end;
end $foreign$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',true);
set local role authenticated;
do $owner$
declare shop uuid:='10000000-0000-0000-0000-0000000000e1';p boolean;
begin
 p:=public.restaurant_capture_cash(shop,current_setting('app.incident_session')::uuid,
   3000,'40000000-0000-0000-0000-0000000000e3');
 if not p then raise exception 'Fully served session not closed';end if;
 if not public.restaurant_review_served_issue(shop,
    current_setting('app.incident_ticket')::uuid,
    'requires_refund_review','Examen du remboursement nécessaire mais pas encore effectué')
 then raise exception 'Owner review failed';end if;
 if (select state from public.restaurant_served_incidents
   where id=current_setting('app.incident_ticket')::uuid)<>'requires_refund_review' then
  raise exception 'Incident review status wrong';end if;
 if (select count(*) from public.restaurant_cash_payments where shop_id=shop)<>1
  or (select sum(amount_xaf) from public.restaurant_cash_payments where shop_id=shop)<>3000
  or (select status from public.restaurant_table_sessions
      where id=current_setting('app.incident_session')::uuid)<>'closed_paid'
  or (select drink_stock from public.restaurant_menu_items
      where id='30000000-0000-0000-0000-0000000000e1')<>3 then
  raise exception 'Issue review silently modified actual cash or inventory';end if;
 if (select count(*) from public.restaurant_staff_events
    where event_type='served_issue_reported')<>1
    or (select count(*) from public.restaurant_staff_events
      where event_type='served_issue_reviewed')<>1 then
  raise exception 'Incident audit missing or duplicated';end if;
end $owner$;
rollback;
