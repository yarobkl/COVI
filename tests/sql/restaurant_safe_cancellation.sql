-- Safe cancellation regression suite, disposable PostgreSQL only.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000d1'),
 ('00000000-0000-0000-0000-0000000000d2');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000d1','00000000-0000-0000-0000-0000000000d1','Resto annulations A','restaurant'),
 ('10000000-0000-0000-0000-0000000000d2','00000000-0000-0000-0000-0000000000d2','Resto annulations B','restaurant');
insert into public.restaurant_tables(id,shop_id,label,capacity) values
 ('20000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d1','1',4),
 ('20000000-0000-0000-0000-0000000000d2','10000000-0000-0000-0000-0000000000d2','1',4);
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock) values
 ('30000000-0000-0000-0000-0000000000d1','10000000-0000-0000-0000-0000000000d1','Poisson','Plat','dish',6000,null),
 ('30000000-0000-0000-0000-0000000000d2','10000000-0000-0000-0000-0000000000d1','Jus','Boisson','drink',1000,6);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d1',true);
set local role authenticated;
do $run$
declare shop uuid:='10000000-0000-0000-0000-0000000000d1';
  sess uuid;person uuid;food uuid;drink uuid;extra uuid;res jsonb;
begin
 sess:=public.restaurant_open_table(shop,'20000000-0000-0000-0000-0000000000d1',2);
 person:=public.restaurant_add_participant(shop,sess);
 food:=public.restaurant_choose_item(shop,sess,person,'30000000-0000-0000-0000-0000000000d1',1);
 drink:=public.restaurant_choose_item(shop,sess,person,'30000000-0000-0000-0000-0000000000d2',2);
 perform public.restaurant_mark_ready(shop,sess,person);
 perform public.restaurant_submit_group(shop,sess,person);
 if (select reserved_drink_stock from public.restaurant_menu_items
    where id='30000000-0000-0000-0000-0000000000d2')<>2 then
   raise exception 'Drink stock not initially reserved'; end if;
 -- Same restaurant, one waiter, first correction of drink never served.
 res:=public.restaurant_cancel_order_line(shop,drink,'Client retire les jus');
 if res->>'cancelled'<>'true' or res->>'tableReleased'<>'false' then
  raise exception 'Unexpected cancellation status'; end if;
 if (select reserved_drink_stock from public.restaurant_menu_items
    where id='30000000-0000-0000-0000-0000000000d2')<>0 then
   raise exception 'Drink reservation not returned to stock'; end if;
 if (select drink_stock from public.restaurant_menu_items
    where id='30000000-0000-0000-0000-0000000000d2')<>6 then
   raise exception 'Cancelling unserved drinks changed physical stock'; end if;
 if (select count(*) from public.restaurant_session_lines
  where id=drink and status='cancelled')<>1 then raise exception 'Cancelled line not preserved'; end if;
 if (select count(*) from public.restaurant_staff_events
  where line_id=drink and event_type='line_cancelled'
   and details->>'reason'='Client retire les jus')<>1 then
  raise exception 'Correction not attributable to user';end if;
 -- Must not return stock again on a retry, even if a slow mobile UI retries.
 begin
  perform public.restaurant_cancel_order_line(shop,drink,'Client retire les jus');
  raise exception 'Repeated cancellation accepted';
 exception when raise_exception then
  if sqlerrm not like '%Only an unserved%' then raise; end if;
 end;
 begin
  perform public.restaurant_cancel_order_line(
    '10000000-0000-0000-0000-0000000000d2',food,'Client change avis');
  raise exception 'Cross-restaurant cancel accepted';
 exception when insufficient_privilege then null;end;
 -- Corrections cannot delete already SERVED food.
 perform public.restaurant_mark_served(shop,food);
 begin
  perform public.restaurant_cancel_order_line(shop,food,'Déjà servi au client');
  raise exception 'Served food removed from history';
 exception when raise_exception then
  if sqlerrm not like '%Only an unserved%' then raise;end if;
 end;
 -- Accept genuine cash payment of 2,000 against 6,000 while table stays locked.
 if public.restaurant_capture_cash(shop,sess,2000,
   '40000000-0000-0000-0000-0000000000d1') then
  raise exception 'Part payment released table'; end if;
 extra:=public.restaurant_staff_add_item(shop,sess,
   '30000000-0000-0000-0000-0000000000d2',1);
 begin
  perform public.restaurant_cancel_order_line(shop,extra,'Montant déjà encaissé');
  -- This is safe: after cancellation 6000 remains and 2000 already paid.
 exception when others then raise exception 'Safe cancellation incorrectly blocked: %',sqlerrm;
 end;
 if (select count(*) from public.restaurant_cash_payments where session_id=sess)<>1
  or (select status from public.restaurant_table_sessions where id=sess)<>'submitted' then
  raise exception 'Corrected bill broke part payment or unlocked table';end if;
 if not public.restaurant_capture_cash(shop,sess,4000,
  '40000000-0000-0000-0000-0000000000d2') then
  raise exception 'Corrected balance not fully settled'; end if;
 if (select status from public.restaurant_table_sessions where id=sess)<>'closed_paid' then
  raise exception 'Corrected table not released on final payment'; end if;
 begin
  perform public.restaurant_cancel_order_line(shop,food,'Après clôture');
  raise exception 'Closed bill allowed editing';
 exception when raise_exception then
  if sqlerrm not like '%Only an active submitted%' then raise;end if;
 end;
end $run$;
-- A second unpaid group may completely cancel and automatically free the QR/table.
do $empty$
declare shop uuid:='10000000-0000-0000-0000-0000000000d1';
sess uuid;part uuid;line uuid;result jsonb;
begin
 sess:=public.restaurant_open_table(shop,'20000000-0000-0000-0000-0000000000d1',1);
 part:=public.restaurant_add_participant(shop,sess);
 line:=public.restaurant_choose_item(shop,sess,part,
 '30000000-0000-0000-0000-0000000000d2',2);
 perform public.restaurant_mark_ready(shop,sess,part);
 perform public.restaurant_submit_group(shop,sess,part);
 result:=public.restaurant_cancel_order_line(shop,line,'Client ne prend plus rien');
 if result->>'tableReleased'<>'true' then raise exception 'Fully cancelled table remained locked';end if;
 if (select status from public.restaurant_table_sessions where id=sess)<>'closed_cancelled'
 then raise exception 'Session not closed as cancelled';end if;
 if (select reserved_drink_stock from public.restaurant_menu_items
 where id='30000000-0000-0000-0000-0000000000d2')<>0
 then raise exception 'Outstanding reservation after full cancellation';end if;
 -- Newly opened collecting session can be cancelled without assigning order number.
 sess:=public.restaurant_open_table(shop,'20000000-0000-0000-0000-0000000000d1',1);
 if not public.restaurant_cancel_empty_table(shop,sess,'Groupe parti avant commande') then
  raise exception 'Empty table not cancelled';end if;
 if (select status from public.restaurant_table_sessions where id=sess)<>'closed_cancelled'
  or (select order_number from public.restaurant_table_sessions where id=sess) is not null
 then raise exception 'Pre-order cancellation assigned order number';end if;
 perform public.restaurant_open_table(shop,'20000000-0000-0000-0000-0000000000d1',1);
end $empty$;
rollback;
