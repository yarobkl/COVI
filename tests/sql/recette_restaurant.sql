-- Recette Restaurant RES-001..RES-012 (docs/recette/RESTAURANT.md, PR #67), côté serveur.
-- Base jetable uniquement, données fictives, tout est annulé (ROLLBACK).
-- Hors périmètre SQL : rendu 390/1280 px (RES-001), impression (RES-010), coupure réseau du
-- navigateur (RES-012) ; RES-003 est aussi couvert par restaurant_concurrency.sh (deux sessions).
\set ON_ERROR_STOP 1
begin;
create function pg_temp.check(ok boolean, label text) returns void language plpgsql as $$
begin
 if ok is not true then raise exception 'FAIL %',coalesce(label,'(libellé nul : valeur lue nulle)'); end if;
 raise notice 'ok %',label;
end $$;
create function pg_temp.expect_denied(sql_text text, label text) returns void language plpgsql as $$
declare code text;
begin
 begin execute sql_text;
 exception when others then
  get stacked diagnostics code = returned_sqlstate;
  if code='42501' then raise notice 'ok %',label; return; end if;
  raise exception 'FAIL %: SQLSTATE % inattendu (%)',label,code,sqlerrm;
 end;
 raise exception 'FAIL %: opération interdite acceptée',label;
end $$;
create function pg_temp.expect_error(sql_text text, pattern text, label text) returns void
language plpgsql as $$
begin
 begin execute sql_text;
 exception when others then
  if sqlerrm like pattern then raise notice 'ok %',label; return; end if;
  raise exception 'FAIL %: erreur inattendue %',label,sqlerrm;
 end;
 raise exception 'FAIL %: opération acceptée',label;
end $$;
grant execute on all functions in schema pg_temp to authenticated, service_role;

insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000004a1'),  -- propriétaire restaurant A
 ('00000000-0000-0000-0000-0000000004a2'),  -- serveur A
 ('00000000-0000-0000-0000-0000000004a3'),  -- cuisine A
 ('00000000-0000-0000-0000-0000000004b1');  -- propriétaire restaurant B
insert into public.shops(id,owner_id,name,business_kind) values
 ('10000000-0000-0000-0000-0000000004a1','00000000-0000-0000-0000-0000000004a1','Recette Resto A (test)','restaurant'),
 ('10000000-0000-0000-0000-0000000004b1','00000000-0000-0000-0000-0000000004b1','Recette Resto B (test)','restaurant');
insert into public.restaurant_menu_items(id,shop_id,name,category,kind,price_xaf,drink_stock,available) values
 ('30000000-0000-0000-0000-0000000004a1','10000000-0000-0000-0000-0000000004a1','Poulet DG','Plats','dish',4500,null,true),
 ('30000000-0000-0000-0000-0000000004a2','10000000-0000-0000-0000-0000000004a1','Poisson braisé','Plats','dish',4500,null,true),
 ('30000000-0000-0000-0000-0000000004a3','10000000-0000-0000-0000-0000000004a1','Primus','Boissons','drink',1500,10,true),
 ('30000000-0000-0000-0000-0000000004a4','10000000-0000-0000-0000-0000000004a1','Plat retiré','Plats','dish',9000,null,false),
 ('30000000-0000-0000-0000-0000000004b1','10000000-0000-0000-0000-0000000004b1','Plat de B','Plats','dish',7000,null,true);
insert into public.restaurant_tables(id,shop_id,label,capacity,qr_token) values
 ('20000000-0000-0000-0000-0000000004b1','10000000-0000-0000-0000-0000000004b1','T1',4,repeat('b',64));
insert into public.restaurant_staff_members(shop_id,user_id,display_name,staff_role,created_by) values
 ('10000000-0000-0000-0000-0000000004a1','00000000-0000-0000-0000-0000000004a2','Serveur test','waiter','00000000-0000-0000-0000-0000000004a1'),
 ('10000000-0000-0000-0000-0000000004a1','00000000-0000-0000-0000-0000000004a3','Cuisine test','kitchen','00000000-0000-0000-0000-0000000004a1');

-- RES-005 / RES-006 / RES-007 : surface publique fermée par défaut.
select pg_temp.check(
 not has_function_privilege('anon','public.restaurant_qr_catalog(text)','execute')
 and not has_function_privilege('authenticated','public.restaurant_qr_catalog(text)','execute')
 and has_function_privilege('service_role','public.restaurant_qr_catalog(text)','execute'),
 'RES-005 carte QR lisible seulement par la passerelle serveur');
select pg_temp.check(
 not has_table_privilege('anon','public.restaurant_tables','select')
 and not has_table_privilege('anon','public.restaurant_menu_items','select')
 and not has_table_privilege('anon','public.restaurant_table_sessions','select')
 and not has_table_privilege('anon','public.restaurant_cash_payments','select'),
 'RES-005 aucune table restaurant lisible en anonyme');
select pg_temp.check(
 not has_function_privilege('anon','public.restaurant_guest_join(text,text)','execute')
 and not has_function_privilege('authenticated','public.restaurant_guest_join(text,text)','execute')
 and not has_function_privilege('anon','public.restaurant_guest_submit(text,text)','execute')
 and not has_function_privilege('authenticated','public.restaurant_guest_submit(text,text)','execute')
 and not has_function_privilege('anon','public.restaurant_guest_choose_item(text,text,uuid,integer)','execute')
 and not has_function_privilege('service_role','public.restaurant_commit_group(uuid,uuid,uuid)','execute'),
 'RES-007 commande de groupe QR non appelable sans la passerelle (désactivée par défaut)');

-- RES-001 : le propriétaire crée 6 tables puis ouvre T1.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004a1',true);
set local role authenticated;
insert into public.restaurant_tables(shop_id,label,zone,capacity,pos_x,pos_y)
select '10000000-0000-0000-0000-0000000004a1','T'||i,case when i<=3 then 'Salle' else 'Terrasse' end,
 4,(array[10,40,70,10,40,70])[i],(array[15,15,15,60,60,60])[i]
from generate_series(1,6) i;
select pg_temp.check(
 (select count(*) from public.restaurant_tables where shop_id='10000000-0000-0000-0000-0000000004a1')=6
 and (select count(distinct label) from public.restaurant_tables where shop_id='10000000-0000-0000-0000-0000000004a1')=6,
 'RES-001 six tables distinctes');
select pg_temp.check(
 (select count(distinct (pos_x,pos_y)) from public.restaurant_tables
   where shop_id='10000000-0000-0000-0000-0000000004a1')=6,
 'RES-001 positions de plan distinctes (pas de superposition en base)');
select pg_temp.expect_error(
 $q$insert into public.restaurant_tables(shop_id,label,capacity)
    values('10000000-0000-0000-0000-0000000004a1','T1',2)$q$,
 '%restaurant_tables%','RES-001 doublon de nom de table refusé');
select pg_temp.check(
 (select count(distinct qr_token) from public.restaurant_tables
   where shop_id='10000000-0000-0000-0000-0000000004a1')=6,
 'RES-001 un QR distinct par table');
do $res001$
declare s uuid;
begin
 s:=public.restaurant_open_table('10000000-0000-0000-0000-0000000004a1',
   (select id from public.restaurant_tables where shop_id='10000000-0000-0000-0000-0000000004a1' and label='T1'),2);
 perform pg_temp.check(s is not null,'RES-001 T1 ouverte');
 perform set_config('app.r_t1',(select id::text from public.restaurant_tables
   where shop_id='10000000-0000-0000-0000-0000000004a1' and label='T1'),true);
 perform set_config('app.r_sess',s::text,true);
end $res001$;

-- RES-002 / RES-004 / RES-008 / RES-012 : commande, cuisine, service, encaissement.
do $order$
declare shop constant uuid:='10000000-0000-0000-0000-0000000004a1';
 sess uuid:=current_setting('app.r_sess')::uuid;
 p uuid; l_dish1 uuid; l_dish2 uuid; l_drink uuid; l_extra uuid;
 total bigint; ref text; ref2 text; res jsonb;
begin
 p:=public.restaurant_add_participant(shop,sess);
 l_dish1:=public.restaurant_choose_item(shop,sess,p,'30000000-0000-0000-0000-0000000004a1',1);
 l_dish2:=public.restaurant_choose_item(shop,sess,p,'30000000-0000-0000-0000-0000000004a2',1);
 l_drink:=public.restaurant_choose_item(shop,sess,p,'30000000-0000-0000-0000-0000000004a3',1);
 perform pg_temp.expect_error(format(
  'select public.restaurant_choose_item(%L,%L,%L,%L,1)',shop,sess,p,'30000000-0000-0000-0000-0000000004a4'),
  '%Item unavailable%','RES-002 plat indisponible refusé');
 perform public.restaurant_mark_ready(shop,sess,p);
 ref:=public.restaurant_submit_group(shop,sess,p);
 perform pg_temp.check(ref like 'CMD-%','RES-004 commande envoyée en cuisine avec une référence');
 -- RES-012 : renvoi de l'envoi (réponse réseau perdue). Observé : côté personnel, le renvoi est
 -- refusé (« Session not collecting ») sans seconde commande ; côté QR invité, il renvoie la même
 -- référence. OBSERVATION (non prouvée en interface) : l'écran doit traiter ce refus comme
 -- « déjà envoyée » et recharger l'état. De même restaurant_staff_add_item n'a pas de clé
 -- d'opération : un ajout rejoué après réponse perdue créerait une seconde ligne.
 begin
  ref2:=public.restaurant_submit_group(shop,sess,p);
  perform pg_temp.check(ref2=ref,'RES-012 renvoi de la commande : même référence, pas de seconde commande');
 exception when raise_exception then
  perform pg_temp.check(sqlerrm not like 'FAIL%' and
   (select count(distinct order_reference) from public.restaurant_table_sessions where id=sess)=1,
   'RES-012 renvoi de la commande refusé sans seconde commande ('||sqlerrm||')');
 end;
 select sum(quantity*unit_price_xaf) into total from public.restaurant_session_lines
  where session_id=sess and status<>'cancelled';
 perform pg_temp.check(total=10500,'RES-002 total 4 500 + 4 500 + 1 500 = 10 500 XAF (obtenu '||total||')');
 perform pg_temp.check((select count(*) from public.restaurant_session_lines where session_id=sess)=3,
  'RES-002 trois lignes, aucune en double');
 perform pg_temp.check((select reserved_drink_stock from public.restaurant_menu_items
   where id='30000000-0000-0000-0000-0000000004a3')=1,'RES-002 boisson réservée, pas encore sortie du stock');

 -- RES-008 : le serveur ajoute puis annule une ligne avant encaissement.
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004a2',true);
 l_extra:=public.restaurant_staff_add_item(shop,sess,'30000000-0000-0000-0000-0000000004a3',2);
 res:=public.restaurant_cancel_order_line(shop,l_extra,'Client renonce aux deux bières');
 perform pg_temp.check(res->>'cancelled'='true','RES-008 ligne annulée avant encaissement');
 perform pg_temp.expect_error(format('select public.restaurant_cancel_order_line(%L,%L,%L)',
   shop,l_extra,'Double clic sur annuler'),'%Only an unserved%','RES-008 seconde annulation refusée');
 -- Contrôles lus par le propriétaire (le serveur ne lit pas les lignes en direct).
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004a1',true);
 select sum(quantity*unit_price_xaf) into total from public.restaurant_session_lines
  where session_id=sess and status<>'cancelled';
 perform pg_temp.check(total=10500,'RES-008 total recalculé à 10 500 (obtenu '||total||')');
 perform pg_temp.check((select count(*) from public.restaurant_staff_events
   where line_id=l_extra and event_type='line_cancelled')=1,'RES-008 annulation journalisée et attribuée');
 perform pg_temp.check((select reserved_drink_stock from public.restaurant_menu_items
   where id='30000000-0000-0000-0000-0000000004a3')=1,'RES-008 réservation de boisson rendue');

 -- RES-004 : la cuisine ne peut pas encaisser ; caisse refusée tant que tout n'est pas servi.
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004a3',true);
 perform pg_temp.expect_denied(format('select public.restaurant_capture_cash(%L,%L,10500,%L)',
   shop,sess,'40000000-0000-0000-0000-0000000004a9'),'RES-004 la cuisine ne peut pas encaisser');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004a1',true);
 perform pg_temp.expect_error(format('select public.restaurant_capture_cash(%L,%L,10500,%L)',
   shop,sess,'40000000-0000-0000-0000-0000000004a1'),'%Serve all ordered items%',
   'RES-004 encaissement refusé avant service complet');
 perform pg_temp.check(not exists(select 1 from public.restaurant_cash_payments where session_id=sess),
   'RES-004 aucun encaissement enregistré après refus');
 perform public.restaurant_mark_served(shop,l_dish1);
 perform public.restaurant_mark_served(shop,l_dish2);
 perform public.restaurant_mark_served(shop,l_drink);
 perform public.restaurant_mark_served(shop,l_drink);
 perform pg_temp.check((select count(*) from public.restaurant_drink_movements where session_id=sess)=1
   and (select drink_stock from public.restaurant_menu_items where id='30000000-0000-0000-0000-0000000004a3')=9,
   'RES-004 boisson servie : stock 10 → 9, un seul mouvement malgré le double service');
 perform pg_temp.check(not public.restaurant_capture_cash(shop,sess,5000,'40000000-0000-0000-0000-0000000004a2'),
   'RES-004 paiement partiel 5 000 : table toujours occupée');
 perform pg_temp.check(public.restaurant_capture_cash(shop,sess,5500,'40000000-0000-0000-0000-0000000004a3'),
   'RES-004 solde 5 500 : table réglée');
 -- RES-003 / RES-012 : même identifiant d'opération rejoué (double clic ou réponse perdue).
 perform pg_temp.check(public.restaurant_capture_cash(shop,sess,5500,'40000000-0000-0000-0000-0000000004a3')
   and (select count(*) from public.restaurant_cash_payments where session_id=sess)=2
   and (select sum(amount_xaf) from public.restaurant_cash_payments where session_id=sess)=10500,
   'RES-003/RES-012 encaissement rejoué : aucun double, total encaissé 10 500');
 perform pg_temp.check((select status from public.restaurant_table_sessions where id=sess)='closed_paid',
   'RES-004 état final closed_paid');
 perform pg_temp.check((select count(*) from public.restaurant_staff_events where session_id=sess)>=1,
   'RES-004 actions du personnel auditables');
 perform pg_temp.expect_error(format('select public.restaurant_staff_add_item(%L,%L,%L,1)',
   shop,sess,'30000000-0000-0000-0000-0000000004a1'),'%Table not taking additions%',
   'RES-004 aucun ajout après règlement');
 perform set_config('app.r_line',l_drink::text,true);
end $order$;

-- RES-003 : deux collaborateurs sur T1 (séquentiel ; le verrou concurrent est prouvé par
-- restaurant_concurrency.sh).
do $res003$
declare shop constant uuid:='10000000-0000-0000-0000-0000000004a1';
 t uuid:=current_setting('app.r_t1')::uuid; s uuid;
begin
 s:=public.restaurant_open_table(shop,t,2);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004a2',true);
 perform pg_temp.expect_error(format('select public.restaurant_open_table(%L,%L,3)',shop,t),
   '%Table occupied%','RES-003 second collaborateur : T1 déjà occupée, refus explicite');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004a1',true);
 perform pg_temp.check((select count(*) from public.restaurant_table_sessions
   where table_id=t and status not in ('closed_paid','closed_cancelled'))=1,
   'RES-003 une seule session active sur T1');
 perform public.restaurant_cancel_empty_table(shop,s,'Recette RES-003 terminée');
end $res003$;
reset role;

-- RES-005 / RES-006 : lecture QR par la passerelle (rôle service).
set local role service_role;
do $qr$
declare d jsonb; tok text;
begin
 select qr_token into tok from public.restaurant_tables where id=current_setting('app.r_t1')::uuid;
 d:=public.restaurant_qr_catalog(tok);
 perform pg_temp.check(d->>'restaurantName'='Recette Resto A (test)' and d->>'tableName'='T1',
   'RES-005 QR de T1 : bon restaurant, bonne table');
 perform pg_temp.check(jsonb_array_length(d->'menu')=3
   and not (d->'menu')::text like '%Plat retiré%' and not (d->'menu')::text like '%Plat de B%',
   'RES-005 carte : seulement les 3 articles disponibles de A');
 perform pg_temp.check(not (d ? 'shop_id' or d ? 'qr_token' or d ? 'session_id')
   and d::text not like '%10000000-0000-0000-0000-0000000004a1%'
   and d::text not like '%00000000-0000-0000-0000-0000000004a%'
   and d::text not like '%40000000-%',
   'RES-005 aucun identifiant interne, propriétaire ni paiement exposé');
 perform pg_temp.check(public.restaurant_qr_catalog('bad') is null
   and public.restaurant_qr_catalog(repeat('0',64)) is null
   and public.restaurant_qr_catalog(left(tok,63)||case when right(tok,1)='a' then 'b' else 'a' end) is null,
   'RES-006 QR invalide ou modifié : réponse vide');
 perform pg_temp.check(public.restaurant_qr_catalog(repeat('b',64))->>'restaurantName'='Recette Resto B (test)'
   and public.restaurant_qr_catalog(repeat('b',64))::text not like '%Recette Resto A%',
   'RES-006 QR d''un autre établissement : uniquement ses propres données');
end $qr$;
reset role;

-- RES-009 : après encaissement, incident sur ligne servie puis remboursement espèces.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004a2',true);
set local role authenticated;
do $incident$
declare r jsonb;
begin
 r:=public.restaurant_report_served_issue('10000000-0000-0000-0000-0000000004a1',
   current_setting('app.r_line')::uuid,'Bière tiède, le client demande un remboursement',
   '40000000-0000-0000-0000-0000000004b9');
 perform set_config('app.r_ticket',r->>'ticketId',true);
 perform pg_temp.expect_denied(format(
   'select public.restaurant_confirm_cash_refund(%L,%L,1500,%L,%L,true)',
   '10000000-0000-0000-0000-0000000004a1',r->>'ticketId','Le serveur tente de rembourser',
   '50000000-0000-0000-0000-0000000004a1'),'RES-009 le serveur ne peut pas rembourser');
end $incident$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004a1',true);
do $refund$
declare shop constant uuid:='10000000-0000-0000-0000-0000000004a1';
 tk uuid:=current_setting('app.r_ticket')::uuid; r jsonb;
begin
 perform public.restaurant_review_served_issue(shop,tk,'requires_refund_review',
   'Remboursement de la bière accepté par le propriétaire');
 r:=public.restaurant_confirm_cash_refund(shop,tk,1500,'1 500 rendus en espèces au client',
   '50000000-0000-0000-0000-0000000004a2',true);
 perform pg_temp.check(r->>'confirmed'='true','RES-009 remboursement espèces 1 500 confirmé');
 r:=public.restaurant_confirm_cash_refund(shop,tk,1500,'1 500 rendus en espèces au client',
   '50000000-0000-0000-0000-0000000004a2',true);
 perform pg_temp.check(r->>'alreadyRecorded'='true'
   and (select count(*) from public.restaurant_cash_refunds where shop_id=shop)=1,
   'RES-009 remboursement rejoué : une seule sortie de caisse');
 perform pg_temp.expect_error(format(
   'select public.restaurant_confirm_cash_refund(%L,%L,500,%L,%L,true)',shop,tk,
   'Seconde tentative avec une autre clé','50000000-0000-0000-0000-0000000004a3'),
   '%already has a cash refund%','RES-009 second remboursement du même incident refusé');
 perform pg_temp.check(
   (select sum(amount_xaf) from public.restaurant_cash_payments where shop_id=shop)=10500
   and (select sum(amount_xaf) from public.restaurant_cash_refunds where shop_id=shop)=1500
   and (select count(*) from public.restaurant_session_lines
     where id=current_setting('app.r_line')::uuid and status='served')=1,
   'RES-009 trace non destructive : encaissé 10 500 conservé, remboursé 1 500 à part, ligne servie intacte');
end $refund$;
reset role;

-- RES-011 : le propriétaire de B agit sur T1 de A avec les UUID connus.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000004b1',true);
set local role authenticated;
do $tenant$
declare shop constant uuid:='10000000-0000-0000-0000-0000000004a1';
 t uuid:=current_setting('app.r_t1')::uuid; sess uuid:=current_setting('app.r_sess')::uuid;
begin
 perform pg_temp.check((select count(*) from public.restaurant_tables where shop_id=shop)=0
   and (select count(*) from public.restaurant_table_sessions where shop_id=shop)=0
   and (select count(*) from public.restaurant_cash_payments where shop_id=shop)=0
   and (select count(*) from public.restaurant_menu_items where shop_id=shop)=0,
   'RES-011 B ne lit ni tables, sessions, paiements ni carte de A');
 perform pg_temp.expect_denied(format('select public.restaurant_open_table(%L,%L,2)',shop,t),
   'RES-011 B ne peut pas ouvrir T1 de A');
 perform pg_temp.expect_denied(format('select public.restaurant_capture_cash(%L,%L,100,%L)',
   shop,sess,'40000000-0000-0000-0000-0000000004c1'),'RES-011 B ne peut pas encaisser chez A');
 perform pg_temp.expect_denied(format('select public.restaurant_cancel_order_line(%L,%L,%L)',
   shop,current_setting('app.r_line'),'Tentative depuis B'),'RES-011 B ne peut pas annuler une ligne de A');
 perform pg_temp.expect_denied(format('select public.restaurant_cash_refund_quote(%L,%L)',
   shop,current_setting('app.r_ticket')),'RES-011 B ne peut pas lire les remboursements de A');
 -- B passe son propre shop_id avec la session de A : aucune ligne trouvée, aucune écriture.
 begin
  perform public.restaurant_capture_cash('10000000-0000-0000-0000-0000000004b1',sess,100,
    '40000000-0000-0000-0000-0000000004c2');
  raise exception 'FAIL RES-011 session de A encaissée via le shop_id de B';
 exception when raise_exception then
  if sqlerrm like 'FAIL%' then raise; end if;
  raise notice 'ok RES-011 session de A sous le shop_id de B refusée (%)',sqlerrm;
 end;
 -- Écriture directe : refusée par privilège ou invisible par RLS (0 ligne) ; vérifié ensuite.
 begin update public.restaurant_tables set label='Piraté' where id=t;
 exception when insufficient_privilege then null; end;
 begin delete from public.restaurant_tables where id=t;
 exception when insufficient_privilege or foreign_key_violation then null; end;
end $tenant$;
reset role;
select pg_temp.check(
 (select label from public.restaurant_tables where id=current_setting('app.r_t1')::uuid)='T1'
 and (select sum(amount_xaf) from public.restaurant_cash_payments
   where shop_id='10000000-0000-0000-0000-0000000004a1')=10500
 and (select status from public.restaurant_table_sessions where id=current_setting('app.r_sess')::uuid)='closed_paid',
 'RES-011 état et totaux de A inchangés après les tentatives de B');
rollback;
