-- Recette Boutique exécutée côté serveur : scénarios RET-001..RET-010 et FIN-001 de
-- docs/recette/BOUTIQUE.md et docs/recette/FINANCE.md (PR #67). Chaque message porte l'ID du
-- scénario. Données entièrement fictives ; transaction annulée à la fin.
--
-- Hors SQL (couverts ailleurs, exécutés par tests/sql/run.sh ou npm test) :
--   RET-005 concurrence sur la dernière pièce : tests/sql/cart_concurrency.sh ;
--   RET-006 coupure réseau / reprise (file hors ligne, même identifiant d'opération) :
--           tests/offline.mjs ; l'invariant serveur (rejeu = aucune vente en plus) est RET-003.
--
-- Acteurs :
--   OA propriétaire de la boutique A ; CA caissière de A (remise max 10 %) ;
--   OB propriétaire de la boutique B ; CB caissier de B.
\set ON_ERROR_STOP 1
begin;

create function pg_temp.expect_msg(p_sql text, p_message text, p_label text) returns void
language plpgsql as $$
declare v_state text; v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_message <> p_message then
      raise exception 'FAIL %: « % » (%) au lieu de « % »', p_label, v_message, v_state, p_message;
    end if;
    raise notice 'ok  %  [% %]', p_label, v_state, v_message;
    return;
  end;
  raise exception 'FAIL %: la requête aurait dû échouer (« % »)', p_label, p_message;
end $$;

create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok  %', p_label;
end $$;

-- Nombre de lignes touchées par un UPDATE/DELETE (0 attendu quand la RLS filtre).
create function pg_temp.affected(p_sql text) returns bigint
language plpgsql as $$
declare v_count bigint;
begin
  execute p_sql;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

\set as_pg 'reset role;'
\set as_oa 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000e1'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000e1'', true); end$$; set local role authenticated;'
\set as_ca 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000e2'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000e2'', true); end$$; set local role authenticated;'
\set as_ob 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000e3'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000e3'', true); end$$; set local role authenticated;'
\set as_cb 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000e4'', true); perform set_config(''request.jwt.claim.session_id'', ''00000000-0000-0000-0000-0000000000e4'', true); end$$; set local role authenticated;'

-- Fixtures --------------------------------------------------------------------------------------
insert into auth.users(id) values
  ('00000000-0000-0000-0000-0000000000e1'), ('00000000-0000-0000-0000-0000000000e2'),
  ('00000000-0000-0000-0000-0000000000e3'), ('00000000-0000-0000-0000-0000000000e4');
insert into public.shops(id, owner_id, name) values
  ('10000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000e1', 'Boutique A (test)'),
  ('10000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000e3', 'Boutique B (test)');
-- A : ballon fictif à 60 000 (3 pièces) et ballon sans pièce enregistrée (20 000).
-- B : commande fournisseur à 8 000 pour 2 unités (coût unitaire 4 000, FIN-001).
insert into public.arrivals(id, shop_id, code, kind, global_cost, status) values
  ('20000000-0000-0000-0000-0000000000e1', '10000000-0000-0000-0000-0000000000e1', 'BAL-RET7',
   'balloon', 60000, 'received'),
  ('20000000-0000-0000-0000-0000000000e2', '10000000-0000-0000-0000-0000000000e1', 'BAL-VIDE',
   'balloon', 20000, 'received'),
  ('20000000-0000-0000-0000-0000000000e3', '10000000-0000-0000-0000-0000000000e3', 'CMD-FIN1',
   'supplier_order', 8000, 'received');
insert into public.products(id, shop_id, arrival_id, name, initial_sale_price, quantity_on_hand,
                            is_unique_piece, is_test) values
  -- RET-001 pièce unique ; RET-002/003/004 article stock 3 ; RET-009 article stock 2 ;
  -- RET-010 produit d'exemple ; RET-007 trois pièces du ballon.
  ('30000000-0000-0000-0000-0000000000e1', '10000000-0000-0000-0000-0000000000e1', null,
   'Robe test', 15000, 1, true, false),
  ('30000000-0000-0000-0000-0000000000e2', '10000000-0000-0000-0000-0000000000e1', null,
   'Chemise test', 12000, 3, false, false),
  ('30000000-0000-0000-0000-0000000000e3', '10000000-0000-0000-0000-0000000000e1', null,
   'Pagne test', 5000, 2, false, false),
  ('30000000-0000-0000-0000-0000000000e4', '10000000-0000-0000-0000-0000000000e1', null,
   'Exemple', 2000, 5, false, true),
  ('30000000-0000-0000-0000-0000000000e5', '10000000-0000-0000-0000-0000000000e1',
   '20000000-0000-0000-0000-0000000000e1', 'Ballon pièce 1', 25000, 1, true, false),
  ('30000000-0000-0000-0000-0000000000e6', '10000000-0000-0000-0000-0000000000e1',
   '20000000-0000-0000-0000-0000000000e1', 'Ballon pièce 2', 30000, 1, true, false),
  ('30000000-0000-0000-0000-0000000000e7', '10000000-0000-0000-0000-0000000000e1',
   '20000000-0000-0000-0000-0000000000e1', 'Ballon pièce 3', 20000, 1, true, false),
  ('30000000-0000-0000-0000-0000000000f1', '10000000-0000-0000-0000-0000000000e3',
   '20000000-0000-0000-0000-0000000000e3', 'Article FIN-001', 7000, 2, false, false);
insert into public.shop_expenses(shop_id, category, label, amount) values
  ('10000000-0000-0000-0000-0000000000e3', 'divers', 'Charge FIN-001', 1000);

-- Caissiers : invitation, code à usage unique, PIN personnel, déverrouillage.
:as_oa
select (public.create_member_invite('10000000-0000-0000-0000-0000000000e1', 'Caissière A', false, 10))
  ->> 'code' as code_a \gset
:as_ob
select (public.create_member_invite('10000000-0000-0000-0000-0000000000e3', 'Caissier B'))
  ->> 'code' as code_b \gset
:as_ca
select pg_temp.check((public.redeem_member_invite(:'code_a')) ->> 'status' = 'joined'
  and (public.set_my_pin('10000000-0000-0000-0000-0000000000e1', '5937')) ->> 'status' = 'ok'
  and (public.verify_my_pin('10000000-0000-0000-0000-0000000000e1', '5937')) ->> 'status' = 'ok',
  'fixtures : caissière A inscrite, PIN défini et déverrouillé');
:as_cb
select pg_temp.check((public.redeem_member_invite(:'code_b')) ->> 'status' = 'joined'
  and (public.set_my_pin('10000000-0000-0000-0000-0000000000e3', '6284')) ->> 'status' = 'ok'
  and (public.verify_my_pin('10000000-0000-0000-0000-0000000000e3', '6284')) ->> 'status' = 'ok',
  'fixtures : caissier B inscrit, PIN défini et déverrouillé');

-- RET-001 : pièce unique vendue une fois ----------------------------------------------------------
:as_oa
select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e1","quantity":1,"sold_unit_price":15000}]',
  'cash', '40000000-0000-0000-0000-0000000000e1') as ret1 \gset
select pg_temp.check((select total_amount = 15000 and not is_test from public.sales where id = :'ret1')
  and (select count(*) = 1 and sum(quantity * sold_unit_price) = 15000
       from public.sale_items where sale_id = :'ret1')
  and (select quantity_on_hand = 0 and status = 'sold' from public.products
       where id = '30000000-0000-0000-0000-0000000000e1'),
  'RET-001 vente unique de 15 000, stock 1 → 0, statut sold, une ligne d''historique');
select pg_temp.expect_msg($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e1","quantity":1,"sold_unit_price":15000}]',
  'cash', gen_random_uuid())$$, 'Product unavailable', 'RET-001 pièce vendue non revendable');

-- RET-002 : 2 unités à 11 500 au lieu de 12 000 ----------------------------------------------------
select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e2","quantity":2,"sold_unit_price":11500}]',
  'mobile_money', '40000000-0000-0000-0000-0000000000e2') as ret2 \gset
select pg_temp.check((select total_amount = 23000 from public.sales where id = :'ret2')
  and (select count(*) = 1 and sum(i.quantity * (p.initial_sale_price - i.sold_unit_price)) = 1000
       from public.sale_items i join public.products p on p.id = i.product_id
       where i.sale_id = :'ret2')
  and (select quantity_on_hand = 1 from public.products
       where id = '30000000-0000-0000-0000-0000000000e2'),
  'RET-002 encaissé 23 000, écart au prix affiché 1 000, stock 3 → 1, une seule ligne');

-- RET-003 : rejeu du même client_operation_id ------------------------------------------------------
select count(*) as sales_before from public.sales \gset
select pg_temp.check(public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e2","quantity":2,"sold_unit_price":11500}]',
  'mobile_money', '40000000-0000-0000-0000-0000000000e2') = :'ret2'::uuid,
  'RET-003 rejeu : même identifiant de vente renvoyé');
select pg_temp.check((select count(*) from public.sales) = :sales_before
  and (select count(*) from public.sale_items where sale_id = :'ret2') = 1
  and (select quantity_on_hand from public.products
       where id = '30000000-0000-0000-0000-0000000000e2') = 1,
  'RET-003 rejeu : aucune vente, ligne ni décrément de stock en plus');

-- RET-004 : dépassement de stock -----------------------------------------------------------------
select pg_temp.expect_msg($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e2","quantity":2,"sold_unit_price":12000}]',
  'cash', '40000000-0000-0000-0000-0000000000e4')$$, 'Insufficient stock',
  'RET-004 vente de 2 unités pour 1 en stock refusée');
select pg_temp.check((select count(*) from public.sales) = :sales_before
  and not exists (select 1 from public.sales
                  where client_operation_id = '40000000-0000-0000-0000-0000000000e4')
  and (select quantity_on_hand from public.products
       where id = '30000000-0000-0000-0000-0000000000e2') = 1,
  'RET-004 stock inchangé (1), aucun encaissement enregistré');

-- RET-007 : ballon à 60 000, ventes 25 000 + 30 000 + 20 000 ---------------------------------------
select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e5","quantity":1,"sold_unit_price":25000}]',
  'cash', '40000000-0000-0000-0000-0000000000e5') is not null as ok \gset
select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e6","quantity":1,"sold_unit_price":30000}]',
  'cash', '40000000-0000-0000-0000-0000000000e6') is not null as ok \gset
select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e7","quantity":1,"sold_unit_price":20000}]',
  'mobile_money', '40000000-0000-0000-0000-0000000000e7') is not null as ok \gset
select pg_temp.check((select cost = 60000 and revenue = 75000 and profit = 15000
                        and recovery_percent = 125 and remaining_to_recover = 0
                        and sold_units = 3 and remaining_units = 0
                      from public.arrival_profitability('10000000-0000-0000-0000-0000000000e1')
                      where code = 'BAL-RET7'),
  'RET-007 ballon : recettes 75 000, coût 60 000 récupéré (125 %), excédent sur coût 15 000');
-- L'excédent du ballon n'est pas un bénéfice net : les charges sont déduites à part, dans
-- shop_estimated_profit (netProfit = grossProfit - charges), contrôlé en FIN-001.
-- Ballon sans pièce enregistrée : aucun coût unitaire inventé, coût signalé à part.
select pg_temp.check((select count(*) = 0 from public.arrival_cost_allocation(
                        '10000000-0000-0000-0000-0000000000e1')
                      where arrival_id = '20000000-0000-0000-0000-0000000000e2')
  and (public.shop_estimated_profit('10000000-0000-0000-0000-0000000000e1')
       ->> 'unallocatedArrivalCost')::numeric = 20000,
  'FIN-001 ballon non ventilé : aucun coût unitaire, 20 000 signalés en unallocatedArrivalCost');

-- RET-009 : caissière plafonnée à 10 % vend à -50 % ---------------------------------------------
-- ANOMALIE / ÉCART DE SPÉCIFICATION : BOUTIQUE.md attend un refus au-delà du plafond. La migration
-- 20261015120000_shop_requested_order_fixes a supprimé le prix minimum (min_unit_price renvoie
-- toujours NULL, « décision de la boutique », cf. tests/sql/members.sql). Le test constate le
-- comportement en place sans le modifier : arbitrage propriétaire requis.
:as_ca
select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e3","quantity":1,"sold_unit_price":2500}]',
  'cash', '40000000-0000-0000-0000-0000000000e9') as ret9 \gset
:as_pg
select pg_temp.check((select total_amount = 2500 and seller_id = '00000000-0000-0000-0000-0000000000e2'
                      from public.sales where id = :'ret9')
  and (select max_discount_pct = 10 from public.shop_members
       where user_id = '00000000-0000-0000-0000-0000000000e2')
  and (select quantity_on_hand = 1 from public.products
       where id = '30000000-0000-0000-0000-0000000000e3'),
  'RET-009 ÉCART constaté : remise de 50 % acceptée malgré un plafond de 10 % (plafond supprimé en 20261015120000)');

-- RET-010 : produit d'exemple exclu des indicateurs --------------------------------------------
:as_oa
select pg_temp.expect_msg($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e4","quantity":1,"sold_unit_price":2000},
    {"product_id":"30000000-0000-0000-0000-0000000000e3","quantity":1,"sold_unit_price":5000}]',
  'cash', gen_random_uuid())$$, 'Cannot mix test and real products',
  'RET-010 panier mêlant exemple et réel refusé');
select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e4","quantity":1,"sold_unit_price":2000}]',
  'cash', '40000000-0000-0000-0000-0000000000ea') as ret10 \gset
-- Ventes réelles du jour : 15 000 + 23 000 + 75 000 + 2 500 = 115 500 (6 ventes).
select pg_temp.check((select is_test from public.sales where id = :'ret10')
  and (public.shop_dashboard('10000000-0000-0000-0000-0000000000e1') ->> 'todaySales')::numeric = 115500
  and (public.shop_dashboard('10000000-0000-0000-0000-0000000000e1') ->> 'todayCount')::int = 6
  and (public.shop_dashboard('10000000-0000-0000-0000-0000000000e1', p_include_test => true)
       ->> 'todaySales')::numeric = 117500
  and (public.shop_estimated_profit('10000000-0000-0000-0000-0000000000e1') ->> 'revenue')::numeric = 115500,
  'RET-010 vente d''exemple marquée is_test, hors indicateurs (115 500 réels ; 117 500 avec exemples)');

-- RET-008 : la boutique B ne lit ni n'écrit rien de A ------------------------------------------
:as_ob
select pg_temp.check((select count(*) from public.products
                      where shop_id = '10000000-0000-0000-0000-0000000000e1') = 0
  and (select count(*) from public.sales where shop_id = '10000000-0000-0000-0000-0000000000e1') = 0
  and (select count(*) from public.sale_items i join public.sales s on s.id = i.sale_id
       where s.shop_id = '10000000-0000-0000-0000-0000000000e1') = 0
  and (select count(*) from public.arrivals where shop_id = '10000000-0000-0000-0000-0000000000e1') = 0
  and (select count(*) from public.shop_members where shop_id = '10000000-0000-0000-0000-0000000000e1') = 0,
  'RET-008 propriétaire B : aucun produit, vente, ligne, arrivage ni membre de A visible');
select pg_temp.check(pg_temp.affected($$update public.products set initial_sale_price = 1
  where id = '30000000-0000-0000-0000-0000000000e2'$$) = 0,
  'RET-008 propriétaire B : UPDATE d''un produit de A sans effet (RLS)');
select pg_temp.expect_msg(format('delete from public.sales where id = %L', :'ret2'),
  'permission denied for table sales', 'RET-008 propriétaire B : DELETE d''une vente refusé (privilège retiré)');
select pg_temp.expect_msg($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e3","quantity":1,"sold_unit_price":5000}]',
  'cash', gen_random_uuid())$$, 'Shop not found', 'RET-008 propriétaire B : vente en caisse A refusée');
select pg_temp.expect_msg($$select public.shop_dashboard('10000000-0000-0000-0000-0000000000e1')$$,
  'Shop not found', 'RET-008 propriétaire B : tableau de bord de A refusé');
select pg_temp.expect_msg($$select public.create_member_invite('10000000-0000-0000-0000-0000000000e1', 'Intrus')$$,
  'Shop not found', 'RET-008 propriétaire B : invitation dans l''équipe de A refusée');
:as_cb
select pg_temp.check((select count(*) from public.products
                      where shop_id = '10000000-0000-0000-0000-0000000000e1') = 0
  and (select count(*) from public.sales where shop_id = '10000000-0000-0000-0000-0000000000e1') = 0,
  'RET-008 caissier B : rien de A visible');
select pg_temp.expect_msg($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000e1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000e3","quantity":1,"sold_unit_price":5000}]',
  'cash', gen_random_uuid())$$, 'Shop not found', 'RET-008 caissier B : vente en caisse A refusée');
:as_pg
select pg_temp.check((select quantity_on_hand from public.products
                      where id = '30000000-0000-0000-0000-0000000000e3') = 1
  and (select initial_sale_price from public.products
       where id = '30000000-0000-0000-0000-0000000000e2') = 12000
  and exists (select 1 from public.sales where id = :'ret2'),
  'RET-008 état de A inchangé après les tentatives de B');

-- FIN-001 : CA 14 000, coût 8 000, marge 6 000, charges 1 000, résultat 5 000 ----------------
:as_ob
select public.record_cart_sale('10000000-0000-0000-0000-0000000000e3',
  '[{"product_id":"30000000-0000-0000-0000-0000000000f1","quantity":2,"sold_unit_price":7000}]',
  'cash', '40000000-0000-0000-0000-0000000000f1') is not null as ok \gset
select pg_temp.check((select unit_cost = 4000 and sold_cost = 8000
                      from public.arrival_cost_allocation('10000000-0000-0000-0000-0000000000e3')
                      where product_id = '30000000-0000-0000-0000-0000000000f1'),
  'FIN-001 coût unitaire affecté 4 000, coût des unités vendues 8 000');
select pg_temp.check((select (r ->> 'revenue')::numeric = 14000
                        and (r ->> 'costOfGoodsSold')::numeric = 8000
                        and (r ->> 'grossProfit')::numeric = 6000
                        and (r ->> 'charges')::numeric = 1000
                        and (r ->> 'netProfit')::numeric = 5000
                      from public.shop_estimated_profit('10000000-0000-0000-0000-0000000000e3') r),
  'FIN-001 CA 14 000, coût 8 000, marge brute 6 000, charges 1 000, résultat 5 000');

rollback;
