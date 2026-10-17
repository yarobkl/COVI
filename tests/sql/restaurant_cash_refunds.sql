-- Restaurant CASH refund: physical payout, idempotency, role & tenant, ledger correctness.
-- Disposable CI database, entire test runs inside ROLLBACK.
\set ON_ERROR_STOP 1
begin;
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000f1'),
 ('00000000-0000-0000-0000-0000000000f2'),
 ('00000000-0000-0000-0000-0000000000f3');
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000f1','Restaurant Cash A','restaurant'),
 ('10000000-0000-0000-0000-0000000000f3','00000000-0000-0000-0000-0000000000f3','Restaurant Cash B','restaurant');
insert into public.restaurant_tables(id,shop_id,label,capacity) values
 ('20000000-0000-0000-0000-0000000000f1','10000000-0000-0000-0000-0000000000f1','08',4);
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock) values
 ('30000000-0000-0000-0000-0000000000f1','10000000-0000-0000-0000-0000000000f1','Jus','Boissons','drink',1500,10);
insert into public.restaurant_staff_members(shop_id,user_id,display_name,staff_role,created_by)
values('10000000-0000-0000-0000-0000000000f1','00000000-0000-0000-0000-0000000000f2',
 'Service F2','waiter','00000000-0000-0000-0000-0000000000f1');
do $guard$
begin
 if has_function_privilege('anon',
  'public.restaurant_confirm_cash_refund(uuid,uuid,bigint,text,uuid,boolean)','execute')
 then raise exception 'Public can confirm physical payouts'; end if;
end $guard$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000f1',true);
set local role authenticated;
do $prepare$
declare shop uuid:='10000000-0000-0000-0000-0000000000f1';
 sess uuid;part uuid;line uuid;
begin
 sess:=public.restaurant_open_table(shop,'20000000-0000-0000-0000-0000000000f1',2);
 part:=public.restaurant_add_participant(shop,sess);
 line:=public.restaurant_choose_item(shop,sess,part,'30000000-0000-0000-0000-0000000000f1',2);
 perform set_config('app.cash_session',sess::text,true);
 perform set_config('app.cash_line',line::text,true);
 perform public.restaurant_mark_ready(shop,sess,part);
 perform public.restaurant_submit_group(shop,sess,part);
 perform public.restaurant_mark_served(shop,line);
 if not public.restaurant_capture_cash(shop,sess,3000,'40000000-0000-0000-0000-0000000000f1')
 then raise exception 'Cash payment not closed';end if;
end $prepare$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000f2',true);
set local role authenticated;
do $report$
declare shop uuid:='10000000-0000-0000-0000-0000000000f1';
 line uuid:=current_setting('app.cash_line')::uuid;r jsonb;
begin
 r:=public.restaurant_report_served_issue(shop,line,
   'Le premier jus était impropre au service et le client se plaint',
   '40000000-0000-0000-0000-0000000000f2');
 perform set_config('app.cash_ticket1',r->>'ticketId',true);
 r:=public.restaurant_report_served_issue(shop,line,
   'Le second jus était lui aussi impropre au service',
   '40000000-0000-0000-0000-0000000000f3');
 perform set_config('app.cash_ticket2',r->>'ticketId',true);
 r:=public.restaurant_report_served_issue(shop,line,
   'Troisième incident sans paiement effectif',
   '40000000-0000-0000-0000-0000000000f4');
 perform set_config('app.cash_ticket3',r->>'ticketId',true);
 begin
  perform public.restaurant_confirm_cash_refund(shop,current_setting('app.cash_ticket1')::uuid,
   1000,'Je suis la serveuse, pas la propriétaire',
   '50000000-0000-0000-0000-0000000000f1',true);
  raise exception 'Waiter confirmed cash refund';
 exception when insufficient_privilege then null;end;
end $report$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000f3',true);
set local role authenticated;
do $other$
begin
 if (select count(*) from public.restaurant_cash_refunds)<>0 then
  raise exception 'Foreign owner can read refund ledger';end if;
 begin
  perform public.restaurant_cash_refund_quote('10000000-0000-0000-0000-0000000000f1',
   current_setting('app.cash_ticket1')::uuid);
  raise exception 'Foreign owner requested cash quote';
 exception when insufficient_privilege then null;end;
end $other$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000f1',true);
set local role authenticated;
do $owner$
declare shop uuid:='10000000-0000-0000-0000-0000000000f1';
 t1 uuid:=current_setting('app.cash_ticket1')::uuid;
 t2 uuid:=current_setting('app.cash_ticket2')::uuid;
 t3 uuid:=current_setting('app.cash_ticket3')::uuid;
 op1 uuid:='50000000-0000-0000-0000-0000000000f1';
 op2 uuid:='50000000-0000-0000-0000-0000000000f2';
 op3 uuid:='50000000-0000-0000-0000-0000000000f3';
 q jsonb; r jsonb;
begin
 perform public.restaurant_review_served_issue(shop,t1,'requires_refund_review',
  'Le client demande un remboursement du jus non conforme');
 perform public.restaurant_review_served_issue(shop,t2,'requires_refund_review',
  'Le client confirme le problème et demande compensation');
 perform public.restaurant_review_served_issue(shop,t3,'requires_refund_review',
  'Autre demande à étudier, qui ne crée aucune sortie de caisse');

 q:=public.restaurant_cash_refund_quote(shop,t1);
 if (q->>'maximumXaf')::bigint<>3000 or (q->>'paidXaf')::bigint<>3000
 then raise exception 'Wrong initial quote';end if;
 begin
  perform public.restaurant_confirm_cash_refund(shop,t1,2000,
   'Espèces non remises, ce n’est qu’une intention',op1,false);
  raise exception 'Unattested payout accepted';
 exception when raise_exception then
  if sqlerrm not like '%Confirmed physical cash payout%' then raise;end if;end;
 begin
  perform public.restaurant_confirm_cash_refund(shop,t1,4000,
   'Ce montant dépasse les trois mille francs reçus',op1,true);
  raise exception 'Over-refund accepted';
 exception when raise_exception then
  if sqlerrm not like '%exceeds amount previously collected%' then raise;end if;end;
 r:=public.restaurant_confirm_cash_refund(shop,t1,2000,
  'Deux mille francs effectivement remis en main propre',op1,true);
 if r->>'confirmed'<>'true' or r->>'alreadyRecorded'<>'false'
 then raise exception 'Cash payout missing confirmation';end if;
 if (public.restaurant_confirm_cash_refund(shop,t1,2000,
  'Deux mille francs effectivement remis en main propre',op1,true))->>'alreadyRecorded'<>'true'
 then raise exception 'Repeated click was not idempotent';end if;
 begin
  perform public.restaurant_confirm_cash_refund(shop,t1,1000,
   'Réutilisation de référence de décaissement avec autre somme',op1,true);
  raise exception 'Tampered operation key accepted';
 exception when raise_exception then
  if sqlerrm not like '%Operation key mismatch%' then raise;end if;end;
 begin
  perform public.restaurant_confirm_cash_refund(shop,t1,1000,
   'Autre opération pour ticket déjà payé une fois',op3,true);
  raise exception 'Double refund for same incident';
 exception when raise_exception then
  if sqlerrm not like '%already has a cash refund%' then raise;end if;end;
 q:=public.restaurant_cash_refund_quote(shop,t2);
 if (q->>'maximumXaf')::bigint<>1000 or (q->>'refundedXaf')::bigint<>2000
 then raise exception 'Quote did not consider first cash-out';end if;
 begin
  perform public.restaurant_confirm_cash_refund(shop,t2,1500,
   'Un deuxième remboursement excessif après décaissement',op2,true);
  raise exception 'Cumulative over-refund accepted';
 exception when raise_exception then
  if sqlerrm not like '%exceeds amount previously collected%' then raise;end if;end;
 perform public.restaurant_confirm_cash_refund(shop,t2,1000,
  'Mille francs remis réellement au même client',op2,true);
 q:=public.restaurant_cash_refund_quote(shop,t3);
 if (q->>'maximumXaf')::bigint<>0 then
  raise exception 'Third incident can overdraw cash';end if;
 if (select sum(amount_xaf) from public.restaurant_cash_refunds where shop_id=shop)<>3000
  or (select sum(amount_xaf) from public.restaurant_cash_payments where shop_id=shop)<>3000
  or (select drink_stock from public.restaurant_menu_items
     where id='30000000-0000-0000-0000-0000000000f1')<>8
  or (select status from public.restaurant_table_sessions
     where id=current_setting('app.cash_session')::uuid)<>'closed_paid' then
  raise exception 'Gross receipts, refunded cash, stock or paid status changed';end if;
 if (select count(*) from public.restaurant_staff_events
      where shop_id=shop and event_type='cash_refund_confirmed')<>2 then
  raise exception 'Double click created duplicate cash event';end if;
end $owner$;
rollback;
