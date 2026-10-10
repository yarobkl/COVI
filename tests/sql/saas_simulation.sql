-- Simulation de bout en bout du modèle SaaS COVI (PR #12) sur une base jetable.
-- Lancée par tests/sql/run.sh après TOUTES les migrations (#6 + #11 + #12 + correctifs).
--
-- Chaque étape est consignée dans pg_temp.sim (étape, attendu, observé, anomalie) au lieu
-- d'interrompre le script au premier écart : on obtient le tableau complet, puis le script
-- échoue à la fin s'il y a au moins une anomalie. Tout est annulé (ROLLBACK) à la fin.
--
-- Acteurs fictifs :
--   S  = Super Admin de test (inséré dans covi_platform_admins par le rôle propriétaire,
--        seule voie prévue : « bootstrap via service_role / SQL admin »)
--   O  = Owner abonné (2 boutiques : A et B)
--   Z  = commerçant V1 historique sans compte SaaS (boutique Z), pour l'isolation inter-comptes
\set ON_ERROR_STOP 1
\set S '00000000-0000-0000-0000-0000000000aa'
\set O '00000000-0000-0000-0000-0000000000a1'
\set Z '00000000-0000-0000-0000-0000000000a2'
begin;

create table pg_temp.sim (
  ord integer, step text, expected text, observed text, anomaly boolean
);
grant select, insert on pg_temp.sim to authenticated, anon;

-- Exécute p_sql et consigne le résultat. p_expect : 'ok' ou un fragment du message d'erreur
-- attendu (ou un SQLSTATE de 5 caractères).
create function pg_temp.try(p_step text, p_expected text, p_sql text, p_expect text)
returns void language plpgsql as $$
declare v_state text; v_msg text; v_obs text; v_bad boolean;
begin
  begin
    execute p_sql;
    v_obs := 'OK';
    v_bad := p_expect <> 'ok';
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_msg = message_text;
    v_obs := 'refusé [' || v_state || ' ' || v_msg || ']';
    v_bad := p_expect = 'ok' or not (v_state = p_expect or position(p_expect in v_msg) > 0);
  end;
  insert into pg_temp.sim values ((select count(*) + 1 from pg_temp.sim), p_step, p_expected,
                                  v_obs, v_bad);
  raise notice '% | % | % | %', p_step, p_expected, v_obs, case when v_bad then 'ANOMALIE' else 'ok' end;
end $$;

-- Consigne une vérification booléenne avec la valeur observée.
create function pg_temp.chk(p_step text, p_expected text, p_ok boolean, p_observed text)
returns void language plpgsql as $$
begin
  insert into pg_temp.sim values ((select count(*) + 1 from pg_temp.sim), p_step, p_expected,
                                  coalesce(p_observed, 'NULL'), p_ok is not true);
  raise notice '% | % | % | %', p_step, p_expected, coalesce(p_observed, 'NULL'),
    case when p_ok is true then 'ok' else 'ANOMALIE' end;
end $$;

-- ===========================================================================================
-- 0. Mise en place (rôle propriétaire = « serveur ») : comptes Auth et Super Admin de test.
-- ===========================================================================================
insert into auth.users(id) values (:'S'), (:'O'), (:'Z');
insert into public.covi_platform_admins(user_id) values (:'S');
insert into public.shops(id, owner_id, name)
  values ('10000000-0000-0000-0000-0000000000a2', :'Z', 'Sim Boutique Z');
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand)
  values ('30000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-0000000000a2',
          'Produit Z', 2000, 10);

-- Contrôles statiques : SECURITY DEFINER + search_path vide, droits EXECUTE, RLS.
select pg_temp.chk('0 statique', 'toutes les fonctions covi_* et create_my_shop : SECURITY DEFINER + search_path=""',
  bool_and(p.prosecdef and p.proconfig = array['search_path=""']),
  string_agg(p.proname || ':' || p.prosecdef || ':' || coalesce(array_to_string(p.proconfig, ','), '-'), ', ' order by p.proname))
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and (p.proname like 'covi\_%' or p.proname = 'create_my_shop');

select pg_temp.chk('0 statique', 'anon : aucun EXECUTE sur les fonctions covi_* et create_my_shop',
  not bool_or(has_function_privilege('anon', p.oid, 'execute')),
  coalesce(string_agg(p.proname, ', ') filter (where has_function_privilege('anon', p.oid, 'execute')), 'aucune'))
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and (p.proname like 'covi\_%' or p.proname = 'create_my_shop');

select pg_temp.chk('0 statique', 'RLS activée sur toutes les tables covi_*',
  bool_and(c.relrowsecurity), string_agg(c.relname || ':' || c.relrowsecurity, ', ' order by c.relname))
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'covi\_%';

select pg_temp.chk('0 statique', 'authenticated : aucun INSERT/UPDATE/DELETE/TRUNCATE sur les tables covi_*',
  not bool_or(has_table_privilege('authenticated', c.oid, 'insert,update,delete,truncate')),
  coalesce(string_agg(c.relname, ', ') filter (
    where has_table_privilege('authenticated', c.oid, 'insert,update,delete,truncate')), 'aucune'))
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'covi\_%';

select pg_temp.chk('0 statique', 'anon : aucun droit sur les tables covi_*',
  not bool_or(has_table_privilege('anon', c.oid, 'select,insert,update,delete')),
  coalesce(string_agg(c.relname, ', ') filter (
    where has_table_privilege('anon', c.oid, 'select,insert,update,delete')), 'aucune'))
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r' and c.relname like 'covi\_%';

select pg_temp.chk('0 statique', 'index unique shops_owner_id_uidx supprimé, index de recherche présent',
  to_regclass('public.shops_owner_id_uidx') is null and to_regclass('public.shops_owner_idx') is not null,
  'uidx=' || coalesce(to_regclass('public.shops_owner_id_uidx')::text, 'absent')
  || ' owner_idx=' || coalesce(to_regclass('public.shops_owner_idx')::text, 'absent')
  || ' lookup_idx=' || coalesce(to_regclass('public.shops_owner_id_lookup_idx')::text, 'absent'));

-- ===========================================================================================
-- 1. Owner fictif O : ne peut ni se promouvoir Super Admin ni appeler les fonctions admin.
-- ===========================================================================================
select set_config('request.jwt.claim.sub', :'O', true);
set local role authenticated;
select pg_temp.chk('1 Owner fictif', 'O n''est pas Super Admin', not public.covi_is_platform_admin(),
  'covi_is_platform_admin()=' || public.covi_is_platform_admin());
select pg_temp.try('1 Owner fictif', 'auto-promotion Super Admin refusée',
  format('insert into public.covi_platform_admins(user_id) values (%L)', :'O'), '42501');
select pg_temp.try('1 Owner fictif', 'O ne peut pas émettre sa propre facture',
  format($$select public.covi_admin_issue_subscription_invoice(%L, 'PIRATE-1', 50,
           now() - interval '1 hour', now() + interval '30 days')$$, :'O'), '42501');
select pg_temp.try('1 Owner fictif', 'O ne peut pas lister les abonnements (vue admin)',
  'select * from public.covi_admin_subscription_overview()', '42501');
select pg_temp.try('1 Owner fictif', 'O ne peut pas créer son propre abonnement',
  $$insert into public.covi_subscriptions(owner_account_id, plan_id, status, shop_limit)
    select gen_random_uuid(), id, 'active', 99 from public.covi_subscription_plans$$, '42501');
reset role;

-- ===========================================================================================
-- 2. Facture mensuelle 15 000 FCFA pour 2 boutiques, émise par le Super Admin S.
-- ===========================================================================================
select set_config('request.jwt.claim.sub', :'S', true);
set local role authenticated;
select pg_temp.chk('2 Facture', 'S est Super Admin', public.covi_is_platform_admin(),
  'covi_is_platform_admin()=' || public.covi_is_platform_admin());
select public.covi_admin_issue_subscription_invoice(:'O', 'SIM-2026-0001', 2,
  now() - interval '1 hour', now() + interval '30 days') as inv1 \gset
select pg_temp.chk('2 Facture', 'montant figé 15 000 XAF, quota 2, statut pending',
  amount_xaf = 15000 and shop_limit = 2 and status = 'pending' and currency = 'XAF',
  amount_xaf || ' ' || currency || ', quota ' || shop_limit || ', ' || status)
from public.covi_subscription_invoices where id = :'inv1';
select pg_temp.try('2 Facture', 'deuxième facture en attente pour le même abonnement refusée',
  format($$select public.covi_admin_issue_subscription_invoice(%L, 'SIM-2026-0001b', 2,
           now() - interval '1 hour', now() + interval '30 days')$$, :'O'), 'Pending invoice already exists');
select pg_temp.chk('2 Facture', 'abonnement créé en pending_payment',
  (select status = 'pending_payment' from public.covi_admin_subscription_overview() where owner_user_id = :'O'),
  (select status || ' / ' || monthly_price_xaf from public.covi_admin_subscription_overview() where owner_user_id = :'O'));

-- O lit sa facture, Z ne la voit pas.
select set_config('request.jwt.claim.sub', :'O', true);
select pg_temp.chk('2 Facture', 'O lit sa propre facture (RLS)',
  (select count(*) from public.covi_subscription_invoices) = 1,
  (select count(*) from public.covi_subscription_invoices)::text || ' facture(s) visible(s)');
select pg_temp.try('2 Facture', 'O ne peut pas modifier sa facture (montant)',
  'update public.covi_subscription_invoices set amount_xaf = 1', '42501');
select pg_temp.try('2 Facture', 'avant paiement : création de boutique refusée',
  $$select public.create_my_shop('Sim Boutique A', 'Brazzaville', 'Congo', 'XAF')$$,
  'Active subscription required');
select set_config('request.jwt.claim.sub', :'Z', true);
select pg_temp.chk('2 Facture', 'Z ne voit ni la facture ni l''abonnement de O',
  (select count(*) from public.covi_subscription_invoices) = 0
  and (select count(*) from public.covi_subscriptions) = 0,
  (select count(*) from public.covi_subscription_invoices) || ' facture(s), '
  || (select count(*) from public.covi_subscriptions) || ' abonnement(s)');
reset role;

-- ===========================================================================================
-- 3. Paiement Mobile Money fictif (hors plateforme). Aucune déclaration côté client possible.
-- ===========================================================================================
select set_config('request.jwt.claim.sub', :'O', true);
set local role authenticated;
select pg_temp.try('3 Paiement MoMo', 'O ne peut pas déclarer/insérer un paiement',
  format($$insert into public.covi_subscription_payments(invoice_id, provider, provider_reference,
           amount_xaf, status, verified_by, verified_at)
           values (%L, 'MTN Mobile Money', 'MP-FAUX', 15000, 'verified', %L, now())$$, :'inv1', :'O'),
  '42501');
select pg_temp.try('3 Paiement MoMo', 'O ne peut pas lire la table des paiements',
  'select count(*) from public.covi_subscription_payments', '42501');

-- ===========================================================================================
-- 4. Confirmation par le Super Admin (après une tentative de O, puis un montant partiel).
-- ===========================================================================================
select pg_temp.try('4 Confirmation', 'O ne peut pas confirmer son propre paiement',
  format($$select public.covi_admin_confirm_mobile_payment(%L, 'MTN Mobile Money', 'MP-SIM-0001', 15000)$$, :'inv1'),
  '42501');
select set_config('request.jwt.claim.sub', :'S', true);
select pg_temp.try('4 Confirmation', 'paiement partiel (10 000) refusé',
  format($$select public.covi_admin_confirm_mobile_payment(%L, 'MTN Mobile Money', 'MP-SIM-PART', 10000)$$, :'inv1'),
  'Payment amount mismatch');
select pg_temp.try('4 Confirmation', 'S confirme 15 000 XAF réf. MP-SIM-0001',
  format($$select public.covi_admin_confirm_mobile_payment(%L, 'MTN Mobile Money', 'MP-SIM-0001', 15000)$$, :'inv1'),
  'ok');
select pg_temp.try('4 Confirmation', 'double confirmation de la même facture refusée',
  format($$select public.covi_admin_confirm_mobile_payment(%L, 'MTN Mobile Money', 'MP-SIM-0002', 15000)$$, :'inv1'),
  'Invoice not pending');
reset role;

-- ===========================================================================================
-- 5. Activation.
-- ===========================================================================================
select pg_temp.chk('5 Activation', 'abonnement active, quota 2, période en cours, facture paid, 1 paiement vérifié',
  s.status = 'active' and s.shop_limit = 2 and s.period_start <= now() and s.period_end > now()
  and i.status = 'paid'
  and (select count(*) from public.covi_subscription_payments p where p.invoice_id = i.id and p.status = 'verified') = 1,
  s.status || ', quota ' || s.shop_limit || ', facture ' || i.status || ', paiements '
  || (select count(*) from public.covi_subscription_payments p where p.invoice_id = i.id))
from public.covi_subscription_invoices i join public.covi_subscriptions s on s.id = i.subscription_id
where i.id = :'inv1';
select pg_temp.chk('5 Activation', 'journal d''audit : facture émise + paiement confirmé par S',
  count(*) filter (where action = 'subscription_invoice_issued') = 1
  and count(*) filter (where action = 'mobile_payment_confirmed' and actor_user_id = :'S') = 1,
  string_agg(action, ', ' order by created_at))
from public.covi_subscription_audit;

select set_config('request.jwt.claim.sub', :'O', true);
set local role authenticated;
select pg_temp.try('5 Activation', 'O ne peut pas augmenter son quota',
  'update public.covi_subscriptions set shop_limit = 10', '42501');
select pg_temp.try('5 Activation', 'O ne peut pas prolonger sa période',
  $$update public.covi_subscriptions set period_end = now() + interval '10 years'$$, '42501');
select pg_temp.try('5 Activation', 'O ne peut pas lire le journal d''audit',
  'select count(*) from public.covi_subscription_audit', '42501');

-- ===========================================================================================
-- 6-8. Boutiques A et B (appel identique au front CreateShopForm), puis 3e refusée.
-- ===========================================================================================
select pg_temp.try('6 Boutique A', 'create_my_shop(p_name,p_city,p_country,p_currency) crée A',
  $$select public.create_my_shop(p_name => 'Sim Boutique A', p_city => 'Brazzaville',
           p_country => 'Congo', p_currency => 'XAF')$$, 'ok');
select pg_temp.try('7 Boutique B', 'create_my_shop crée B',
  $$select public.create_my_shop(p_name => 'Sim Boutique B', p_city => 'Pointe-Noire',
           p_country => 'Congo', p_currency => 'XAF')$$, 'ok');
select pg_temp.try('8 3e boutique', '3e boutique refusée (quota 2)',
  $$select public.create_my_shop('Sim Boutique C', 'Dolisie', 'Congo', 'XAF')$$, 'Shop quota reached');
select pg_temp.try('8 3e boutique', 'INSERT direct dans shops refusé',
  format($$insert into public.shops(owner_id, name) values (%L, 'Sim Boutique pirate')$$, :'O'), '42501');
select pg_temp.chk('8 3e boutique', 'O possède exactement 2 boutiques',
  (select count(*) from public.shops) = 2, (select count(*) from public.shops)::text || ' boutique(s) visibles');
reset role;
select id as shop_a from public.shops where name = 'Sim Boutique A' \gset
select id as shop_b from public.shops where name = 'Sim Boutique B' \gset

-- ===========================================================================================
-- 9. Isolation A/B et inter-comptes (ventes via record_sale / record_cart_sale).
-- ===========================================================================================
select set_config('request.jwt.claim.sub', :'O', true);
set local role authenticated;
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand) values
  ('30000000-0000-0000-0000-0000000000aa', :'shop_a', 'Robe A', 5000, 10),
  ('30000000-0000-0000-0000-0000000000ab', :'shop_b', 'Sac B', 8000, 10);
select pg_temp.try('9 Isolation', 'vente sur A (record_sale) acceptée',
  format($$select public.record_sale(%L, '30000000-0000-0000-0000-0000000000aa', 1, 5000, 'cash',
           '40000000-0000-0000-0000-0000000000a1')$$, :'shop_a'), 'ok');
select pg_temp.try('9 Isolation', 'vente sur B (record_cart_sale) acceptée',
  format($$select public.record_cart_sale(%L,
           '[{"product_id":"30000000-0000-0000-0000-0000000000ab","quantity":1,"sold_unit_price":8000}]',
           'mobile_money', '40000000-0000-0000-0000-0000000000a2')$$, :'shop_b'), 'ok');
select pg_temp.try('9 Isolation', 'record_sale sur A avec un produit de B refusé',
  format($$select public.record_sale(%L, '30000000-0000-0000-0000-0000000000ab', 1, 8000, 'cash',
           '40000000-0000-0000-0000-0000000000a3')$$, :'shop_a'), 'Product unavailable');
select pg_temp.try('9 Isolation', 'record_cart_sale sur A avec un produit de B refusé',
  format($$select public.record_cart_sale(%L,
           '[{"product_id":"30000000-0000-0000-0000-0000000000ab","quantity":1,"sold_unit_price":8000}]',
           'cash', '40000000-0000-0000-0000-0000000000a4')$$, :'shop_a'), 'P0001');
select pg_temp.chk('9 Isolation', 'ventes cloisonnées : 1 vente sur A (5 000), 1 vente sur B (8 000)',
  (select string_agg(total_amount::int::text, ',' order by total_amount) from public.sales where shop_id = :'shop_a') = '5000'
  and (select string_agg(total_amount::int::text, ',' order by total_amount) from public.sales where shop_id = :'shop_b') = '8000',
  'A=' || coalesce((select string_agg(total_amount::int::text, ',') from public.sales where shop_id = :'shop_a'), '-')
  || ' B=' || coalesce((select string_agg(total_amount::int::text, ',') from public.sales where shop_id = :'shop_b'), '-'));
select pg_temp.try('9 Isolation', 'O : record_sale sur la boutique Z d''un autre compte refusé',
  $$select public.record_sale('10000000-0000-0000-0000-0000000000a2', '30000000-0000-0000-0000-0000000000a2',
           1, 2000, 'cash', '40000000-0000-0000-0000-0000000000a5')$$, 'Shop not found');
select set_config('request.jwt.claim.sub', :'Z', true);
select pg_temp.chk('9 Isolation', 'Z ne lit ni les boutiques, ni les produits, ni les ventes de O',
  (select count(*) from public.shops where owner_id = :'O') = 0
  and (select count(*) from public.products where shop_id in (:'shop_a', :'shop_b')) = 0
  and (select count(*) from public.sales where shop_id in (:'shop_a', :'shop_b')) = 0,
  'shops=' || (select count(*) from public.shops where owner_id = :'O')
  || ' produits=' || (select count(*) from public.products where shop_id in (:'shop_a', :'shop_b'))
  || ' ventes=' || (select count(*) from public.sales where shop_id in (:'shop_a', :'shop_b')));
select pg_temp.try('9 Isolation', 'Z : record_sale sur A refusé',
  format($$select public.record_sale(%L, '30000000-0000-0000-0000-0000000000aa', 1, 5000, 'cash',
           '40000000-0000-0000-0000-0000000000a6')$$, :'shop_a'), 'Shop not found');
select pg_temp.try('9 Isolation', 'Z : INSERT d''un produit dans A refusé',
  format($$insert into public.products(shop_id, name, initial_sale_price, quantity_on_hand)
           values (%L, 'intrus', 1, 1)$$, :'shop_a'), '42501');
select pg_temp.try('9 Isolation', 'Z (V1 sans abonnement) continue de vendre dans sa boutique',
  $$select public.record_sale('10000000-0000-0000-0000-0000000000a2', '30000000-0000-0000-0000-0000000000a2',
           1, 2000, 'cash', '40000000-0000-0000-0000-0000000000a7')$$, 'ok');
reset role;

-- ===========================================================================================
-- 10. Suspension par S, puis restrictions côté O.
-- ===========================================================================================
select id as sub_o from public.covi_subscriptions s
  where owner_account_id = (select id from public.covi_owner_accounts where user_id = :'O') \gset
select set_config('request.jwt.claim.sub', :'O', true);
set local role authenticated;
select pg_temp.try('10 Suspension', 'O ne peut pas suspendre/réactiver (fonction admin)',
  format($$select public.covi_admin_suspend_subscription(%L, 'tentative commerçant')$$, :'sub_o'), '42501');
select set_config('request.jwt.claim.sub', :'S', true);
select pg_temp.try('10 Suspension', 'motif trop court refusé',
  format($$select public.covi_admin_suspend_subscription(%L, 'court')$$, :'sub_o'), '22023');
select pg_temp.try('10 Suspension', 'S suspend l''abonnement (motif journalisé)',
  format($$select public.covi_admin_suspend_subscription(%L, 'Impayé simulation audit')$$, :'sub_o'), 'ok');
select set_config('request.jwt.claim.sub', :'O', true);
-- Hors ligne : vente déjà synchronisée AVANT la suspension puis renvoyée (même operation id)
-- -> idempotence : même id renvoyé, rien d'écrit. Vente enregistrée hors ligne avant la
-- suspension mais synchronisée APRÈS -> refus définitif P0001 'Subscription inactive...'.
select pg_temp.chk('10 Hors ligne', 'record_sale rejoué (op déjà synchronisée avant suspension) : même id, aucune écriture',
  public.record_sale(:'shop_a', '30000000-0000-0000-0000-0000000000aa', 1, 5000, 'cash',
    '40000000-0000-0000-0000-0000000000a1')
  = (select id from public.sales where client_operation_id = '40000000-0000-0000-0000-0000000000a1'),
  'ventes A=' || (select count(*) from public.sales where shop_id = :'shop_a'));
select pg_temp.chk('10 Hors ligne', 'record_cart_sale rejoué (op déjà synchronisée) : même id, aucune écriture',
  public.record_cart_sale(:'shop_b',
    '[{"product_id":"30000000-0000-0000-0000-0000000000ab","quantity":1,"sold_unit_price":8000}]',
    'mobile_money', '40000000-0000-0000-0000-0000000000a2')
  = (select id from public.sales where client_operation_id = '40000000-0000-0000-0000-0000000000a2'),
  'ventes B=' || (select count(*) from public.sales where shop_id = :'shop_b'));
select pg_temp.try('10 Hors ligne', 'vente hors ligne (avant suspension) synchronisée après : refus P0001 Subscription inactive',
  format($$select public.record_sale(%L, '30000000-0000-0000-0000-0000000000aa', 2, 5000, 'cash',
           '40000000-0000-0000-0000-0000000000b0')$$, :'shop_a'), 'Subscription inactive: shop is read-only');
select pg_temp.try('10 Hors ligne', 'panier hors ligne synchronisé après suspension : refus P0001 Subscription inactive',
  format($$select public.record_cart_sale(%L,
           '[{"product_id":"30000000-0000-0000-0000-0000000000aa","quantity":1,"sold_unit_price":5000}]',
           'cash', '40000000-0000-0000-0000-0000000000b9')$$, :'shop_a'), 'Subscription inactive: shop is read-only');
select pg_temp.try('10 Suspension', 'record_sale refusé pendant la suspension',
  format($$select public.record_sale(%L, '30000000-0000-0000-0000-0000000000aa', 1, 5000, 'cash',
           '40000000-0000-0000-0000-0000000000b1')$$, :'shop_a'), 'Subscription inactive');
select pg_temp.try('10 Suspension', 'record_cart_sale refusé pendant la suspension',
  format($$select public.record_cart_sale(%L,
           '[{"product_id":"30000000-0000-0000-0000-0000000000ab","quantity":1,"sold_unit_price":8000}]',
           'cash', '40000000-0000-0000-0000-0000000000b2')$$, :'shop_b'), 'Subscription inactive');
select pg_temp.try('10 Suspension', 'INSERT products refusé pendant la suspension',
  format($$insert into public.products(shop_id, name, initial_sale_price, quantity_on_hand)
           values (%L, 'Nouveau', 1000, 1)$$, :'shop_a'), 'Subscription inactive');
select pg_temp.try('10 Suspension', 'UPDATE products (prix) refusé pendant la suspension',
  $$update public.products set initial_sale_price = 1 where id = '30000000-0000-0000-0000-0000000000aa'$$,
  'Subscription inactive');
select pg_temp.try('10 Suspension', 'INSERT arrivals refusé pendant la suspension',
  format($$insert into public.arrivals(shop_id, code, kind) values (%L, 'SIM-ARR', 'balloon')$$, :'shop_a'),
  'Subscription inactive');
select pg_temp.try('10 Suspension', 'INSERT shop_expenses refusé pendant la suspension',
  format($$insert into public.shop_expenses(shop_id, category, label, amount)
           values (%L, 'loyer', 'Loyer', 1000)$$, :'shop_a'), 'Subscription inactive');
select pg_temp.try('10 Suspension', 'DELETE de la boutique A refusé pendant la suspension (pas de perte)',
  format($$delete from public.shops where id = %L$$, :'shop_a'), 'Subscription inactive');
select pg_temp.try('10 Suspension', 'création de boutique refusée pendant la suspension',
  $$select public.create_my_shop('Sim Boutique C', 'Dolisie', 'Congo', 'XAF')$$, 'Active subscription required');

-- ===========================================================================================
-- 11. Conservation des données (lecture conservée, rien supprimé).
-- ===========================================================================================
select pg_temp.chk('11 Conservation', 'O lit toujours 2 boutiques, 2 produits, 2 ventes',
  (select count(*) from public.shops) = 2
  and (select count(*) from public.products) = 2
  and (select count(*) from public.sales) = 2,
  'boutiques=' || (select count(*) from public.shops) || ' produits=' || (select count(*) from public.products)
  || ' ventes=' || (select count(*) from public.sales));
select pg_temp.chk('11 Conservation', 'O lit son abonnement suspendu',
  (select status from public.covi_subscriptions) = 'suspended', (select status from public.covi_subscriptions));
reset role;

-- ===========================================================================================
-- 12. Renouvellement après suspension, puis rétablissement des écritures.
-- ===========================================================================================
select set_config('request.jwt.claim.sub', :'S', true);
set local role authenticated;
select public.covi_admin_issue_subscription_invoice(:'O', 'SIM-2026-0002', 2,
  now() - interval '1 hour', now() + interval '30 days') as inv2 \gset
select pg_temp.try('12 Renouvellement', 'référence MoMo déjà utilisée refusée',
  format($$select public.covi_admin_confirm_mobile_payment(%L, 'MTN Mobile Money', 'MP-SIM-0001', 15000)$$, :'inv2'),
  '23505');
select pg_temp.try('12 Renouvellement', 'S confirme le renouvellement (nouvelle réf.)',
  format($$select public.covi_admin_confirm_mobile_payment(%L, 'MTN Mobile Money', 'MP-SIM-0003', 15000)$$, :'inv2'),
  'ok');
select set_config('request.jwt.claim.sub', :'O', true);
select pg_temp.try('12 Renouvellement', 'record_sale de nouveau accepté',
  format($$select public.record_sale(%L, '30000000-0000-0000-0000-0000000000aa', 1, 5000, 'cash',
           '40000000-0000-0000-0000-0000000000c1')$$, :'shop_a'), 'ok');
select pg_temp.chk('12 Renouvellement', 'données intactes : 3 ventes, stock Robe A = 8',
  (select count(*) from public.sales) = 3
  and (select quantity_on_hand from public.products where id = '30000000-0000-0000-0000-0000000000aa') = 8,
  'ventes=' || (select count(*) from public.sales) || ' stock Robe A='
  || (select quantity_on_hand from public.products where id = '30000000-0000-0000-0000-0000000000aa'));
reset role;

select set_config('request.jwt.claim.sub', :'O', true);
set local role authenticated;
select pg_temp.try('12 Renouvellement', 'reprise : la vente hors ligne refusée (même operation id) passe après renouvellement',
  format($$select public.record_sale(%L, '30000000-0000-0000-0000-0000000000aa', 2, 5000, 'cash',
           '40000000-0000-0000-0000-0000000000b0')$$, :'shop_a'), 'ok');
reset role;

-- 12b. Expiration sans suspension explicite (statut resté 'active', période échue).
update public.covi_subscriptions
  set period_start = now() - interval '31 days', period_end = now() - interval '1 minute'
  where id = :'sub_o';
select set_config('request.jwt.claim.sub', :'O', true);
set local role authenticated;
select pg_temp.try('12b Expiration', 'période échue : record_sale refusé',
  format($$select public.record_sale(%L, '30000000-0000-0000-0000-0000000000aa', 1, 5000, 'cash',
           '40000000-0000-0000-0000-0000000000c2')$$, :'shop_a'), 'Subscription inactive');
select set_config('request.jwt.claim.sub', :'S', true);
select pg_temp.try('12b Expiration', 'émission d''une facture à période entièrement passée (acceptée : aucun contrôle à l''émission)',
  format($$select public.covi_admin_issue_subscription_invoice(%L, 'SIM-2026-OLD', 2,
           now() - interval '60 days', now() - interval '30 days')$$, :'O'), 'ok');
-- Le Super Admin n'a aucune lecture directe des factures (RLS) : identifiant lu en rôle serveur.
reset role;
select id as inv_old from public.covi_subscription_invoices where invoice_number = 'SIM-2026-OLD' \gset
set local role authenticated;
select pg_temp.try('12b Expiration', 'confirmation d''une facture à période passée refusée',
  format($$select public.covi_admin_confirm_mobile_payment(%L, 'MTN Mobile Money', 'MP-SIM-OLD', 15000)$$, :'inv_old'),
  'Invoice period is not currently valid');
reset role;
select pg_temp.chk('12b Expiration', 'après ce refus : facture toujours pending, aucun paiement enregistré (rollback)',
  (select status from public.covi_subscription_invoices where id = :'inv_old') = 'pending'
  and not exists (select 1 from public.covi_subscription_payments where provider_reference = 'MP-SIM-OLD'),
  'facture ' || (select status from public.covi_subscription_invoices where id = :'inv_old')
  || ', paiements MP-SIM-OLD=' || (select count(*) from public.covi_subscription_payments where provider_reference = 'MP-SIM-OLD'));
-- Le Super Admin annule cette facture erronée (aucune fonction prévue : rôle serveur).
update public.covi_subscription_invoices set status = 'cancelled' where id = :'inv_old';

select set_config('request.jwt.claim.sub', :'S', true);
set local role authenticated;
select public.covi_admin_issue_subscription_invoice(:'O', 'SIM-2026-0003', 2,
  now() - interval '1 hour', now() + interval '30 days') as inv3 \gset
select pg_temp.try('12c Renouvellement après expiration', 'S confirme le renouvellement d''un abonnement échu',
  format($$select public.covi_admin_confirm_mobile_payment(%L, 'Airtel Money', 'AM-SIM-0004', 15000)$$, :'inv3'),
  'ok');
select set_config('request.jwt.claim.sub', :'O', true);
select pg_temp.try('12c Renouvellement après expiration', 'record_sale de nouveau accepté',
  format($$select public.record_sale(%L, '30000000-0000-0000-0000-0000000000aa', 1, 5000, 'cash',
           '40000000-0000-0000-0000-0000000000c3')$$, :'shop_a'), 'ok');
reset role;

-- anon : aucune fonction SaaS.
set local role anon;
select pg_temp.try('anon', 'anon : covi_admin_confirm_mobile_payment refusé',
  format($$select public.covi_admin_confirm_mobile_payment(%L, 'x', 'y', 1)$$, :'inv3'), '42501');
reset role;

-- ===========================================================================================
-- Tableau final + verdict.
-- ===========================================================================================
\pset format aligned
\pset tuples_only off
select ord as "#", step as "étape", expected as "attendu", observed as "observé",
  case when anomaly then 'ANOMALIE' else 'non' end as "anomalie"
from pg_temp.sim order by ord;

do $$
declare n integer;
begin
  select count(*) into n from pg_temp.sim where anomaly;
  if n > 0 then
    raise exception 'FAIL saas_simulation : % anomalie(s) sur % étapes', n, (select count(*) from pg_temp.sim);
  end if;
  raise notice 'PASS saas_simulation : % étapes conformes', (select count(*) from pg_temp.sim);
end $$;

rollback;
