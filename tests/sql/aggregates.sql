-- Agrégats calculés en base (migration 20261010090100_shop_aggregates) sur le scénario
-- « trois mois » de three_months.sql : 143 ventes de juillet à septembre 2026.
-- Tout se passe dans une transaction annulée à la fin : la base de test reste vierge.
\set ON_ERROR_STOP 1
begin;

create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok  %', p_label;
end $$;

create function pg_temp.check_eq(p_actual numeric, p_expected numeric, p_label text) returns void
language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL %: % au lieu de %', p_label, p_actual, p_expected;
  end if;
  raise notice 'ok  % = %', p_label, p_actual;
end $$;

-- Scénario (identique à three_months.sql) -------------------------------------------------------
insert into auth.users(id) values ('00000000-0000-0000-0000-0000000000c1');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);
set local role authenticated;

do $$
declare
  shop uuid; china uuid; balloon uuid; india uuid; robe uuid; jean uuid; chemise uuid;
  article uuid; piece uuid; sale uuid; r record; j integer;
begin
  select id into shop from public.create_my_shop('TEST agrégats', 'Brazzaville', 'Congo', 'XAF');
  perform set_config('covi.shop', shop::text, true);
  insert into public.arrivals(shop_id, code, kind, origin_country, order_date, global_cost, status)
  values (shop, 'TEST-CHN', 'supplier_order', 'Chine', '2026-07-01', 620000, 'draft')
  returning id into china;
  update public.arrivals set status = 'ordered' where id = china;
  update public.arrivals set status = 'in_transit' where id = china;
  update public.arrivals set status = 'received', received_date = '2026-07-05' where id = china;
  insert into public.arrivals(shop_id, code, kind, origin_country, global_cost, status, received_date)
  values (shop, 'TEST-BAL', 'balloon', 'Congo', 250000, 'received', '2026-07-18')
  returning id into balloon;
  perform set_config('covi.balloon', balloon::text, true);
  insert into public.arrivals(shop_id, code, kind, origin_country, global_cost, status, received_date)
  values (shop, 'TEST-IND', 'supplier_order', 'Inde', 360000, 'received', '2026-08-15')
  returning id into india;
  insert into public.products(shop_id, arrival_id, name, category, initial_sale_price, quantity_on_hand)
  values (shop, china, 'TEST Robe A', 'Robes', 18000, 20) returning id into robe;
  insert into public.products(shop_id, arrival_id, name, category, initial_sale_price, quantity_on_hand)
  values (shop, china, 'TEST Jean B', 'Jeans', 22000, 15) returning id into jean;
  insert into public.products(shop_id, arrival_id, name, category, initial_sale_price, quantity_on_hand)
  values (shop, china, 'TEST Chemise C', 'Chemises', 12000, 30) returning id into chemise;
  insert into public.products(shop_id, arrival_id, name, category, initial_sale_price, quantity_on_hand)
  values (shop, india, 'TEST Article D', 'Vêtements', 20000, 40) returning id into article;
  for j in 1..50 loop
    insert into public.products(shop_id, arrival_id, name, category, initial_sale_price,
                                quantity_on_hand, is_unique_piece)
    values (shop, balloon, 'TEST Pièce ballon ' || lpad(j::text, 2, '0'), 'Lot mixte', 15000, 1, true);
  end loop;
  for r in select * from (values
      (7,'robe',8,18000),(7,'jean',5,22000),(7,'chemise',10,12000),(7,'balloon',12,10000),
      (8,'robe',7,18000),(8,'jean',5,22000),(8,'chemise',10,12000),(8,'balloon',22,15000),(8,'article',15,20000),
      (9,'robe',5,18000),(9,'jean',4,22000),(9,'chemise',8,12000),(9,'balloon',12,15000),(9,'article',20,20000)
    ) as plan(month, product, qty, price) loop
    for j in 1..r.qty loop
      if r.product = 'balloon' then
        select id into piece from public.products
        where arrival_id = balloon and status = 'active' order by name limit 1;
      else
        piece := case r.product when 'robe' then robe when 'jean' then jean
                                when 'chemise' then chemise else article end;
      end if;
      sale := public.record_sale(shop, piece, 1, r.price,
        (array['cash','mobile_money','card','bank_transfer','other'])[1 + (j % 5)], gen_random_uuid());
      -- Antidatage (préparation des données) : réservé au rôle propriétaire.
      execute 'reset role';
      update public.sales set sold_at = make_date(2026, r.month, 28)::timestamptz where id = sale;
      execute 'set local role authenticated';
    end loop;
  end loop;
  insert into public.shop_expenses(shop_id, category, label, amount, expense_date, recurring) values
    (shop, 'Loyer', 'TEST juillet', 110000, '2026-07-01', true),
    (shop, 'Loyer', 'TEST août', 130000, '2026-08-01', true),
    (shop, 'Loyer', 'TEST septembre', 140000, '2026-09-01', true);
end $$;

-- Ventes mensuelles -----------------------------------------------------------------------------
do $$
declare
  shop uuid := current_setting('covi.shop')::uuid;
  m jsonb := public.shop_monthly_sales(shop, 3, 'Africa/Brazzaville', false, '2026-10-15 12:00+01');
begin
  perform pg_temp.check((m -> 'months' -> 0 ->> 'month') = '2026-07'
    and (m -> 'months' -> 2 ->> 'month') = '2026-09' and jsonb_array_length(m -> 'months') = 3,
    'shop_monthly_sales : juillet à septembre');
  perform pg_temp.check_eq((m -> 'months' -> 0 ->> 'amount')::numeric, 494000, 'ventes juillet');
  perform pg_temp.check_eq((m -> 'months' -> 1 ->> 'amount')::numeric, 986000, 'ventes août');
  perform pg_temp.check_eq((m -> 'months' -> 2 ->> 'amount')::numeric, 854000, 'ventes septembre');
  perform pg_temp.check_eq((m -> 'months' -> 0 ->> 'saleCount')::numeric, 35, 'nb ventes juillet');
  perform pg_temp.check_eq((m -> 'months' -> 1 ->> 'saleCount')::numeric, 59, 'nb ventes août');
  perform pg_temp.check_eq((m -> 'months' -> 2 ->> 'saleCount')::numeric, 49, 'nb ventes septembre');
  perform pg_temp.check((m -> 'topCategories') = '[
      {"category": "Lot mixte", "quantity": 46, "amount": 630000},
      {"category": "Vêtements", "quantity": 35, "amount": 700000},
      {"category": "Chemises", "quantity": 28, "amount": 336000},
      {"category": "Robes", "quantity": 20, "amount": 360000},
      {"category": "Jeans", "quantity": 14, "amount": 308000}]'::jsonb,
    'top catégories sur trois mois');
  perform pg_temp.check((m -> 'months' -> 0 -> 'topCategories' -> 0 ->> 'category') = 'Lot mixte'
    and (m -> 'months' -> 0 -> 'topCategories' -> 0 ->> 'quantity')::int = 12,
    'top catégorie de juillet');
  m := public.shop_monthly_sales(shop, 6, 'Africa/Brazzaville', false, '2026-10-15 12:00+01');
  perform pg_temp.check(jsonb_array_length(m -> 'months') = 6
    and (m -> 'months' -> 0 ->> 'month') = '2026-04'
    and (m -> 'months' -> 0 ->> 'amount')::numeric = 0, 'mois sans vente à zéro');
end $$;

-- Tableau de bord -----------------------------------------------------------------------------
do $$
declare
  shop uuid := current_setting('covi.shop')::uuid;
  d jsonb := public.shop_dashboard(shop, 'Africa/Brazzaville', false, '2026-08-20 10:00+01');
begin
  perform pg_temp.check_eq((d ->> 'monthSales')::numeric, 986000, 'dashboard août : ventes du mois');
  perform pg_temp.check_eq((d ->> 'saleCount')::numeric, 59, 'dashboard août : nb ventes');
  perform pg_temp.check_eq((d ->> 'todaySales')::numeric, 0, 'dashboard 20 août : ventes du jour');
  perform pg_temp.check_eq((d ->> 'charges')::numeric, 130000, 'dashboard août : charges');
  perform pg_temp.check_eq((d ->> 'arrivalCost')::numeric, 360000, 'dashboard août : arrivages reçus');
  perform pg_temp.check_eq((d ->> 'profitBeforeCharges')::numeric, 626000, 'dashboard août : avant charges');
  perform pg_temp.check_eq((d ->> 'profit')::numeric, 496000, 'dashboard août : résultat');
  perform pg_temp.check_eq((d ->> 'stock')::numeric, 12, 'dashboard : stock disponible');
  perform pg_temp.check_eq((d ->> 'arrivalsInProgress')::numeric, 0, 'dashboard : arrivages en cours');
  perform pg_temp.check_eq((d ->> 'previousMonthSales')::numeric, 494000, 'dashboard août : ventes de juillet');
  perform pg_temp.check_eq((d ->> 'restAfterCharges')::numeric, 856000, 'dashboard août : reste après charges');
  perform pg_temp.check((d -> 'expensesByCategory') = '[{"category": "Loyer", "amount": 130000}]'::jsonb,
    'dashboard août : charges par catégorie');

  d := public.shop_dashboard(shop, 'Africa/Brazzaville', false, '2026-07-28 15:00+01');
  perform pg_temp.check_eq((d ->> 'todaySales')::numeric, 494000, 'dashboard 28 juillet : ventes du jour');
  perform pg_temp.check_eq((d ->> 'todayCount')::numeric, 35, 'dashboard 28 juillet : nb ventes du jour');
  perform pg_temp.check_eq((select sum((x ->> 'amount')::numeric) from jsonb_array_elements(d -> 'todayByPaymentMethod') x),
    494000, 'dashboard 28 juillet : répartition par moyen de paiement');
  perform pg_temp.check(jsonb_array_length(d -> 'todayByPaymentMethod') = 5,
    'dashboard 28 juillet : 5 moyens de paiement');
  perform pg_temp.check_eq((d ->> 'monthSales')::numeric, 494000, 'dashboard juillet : ventes du mois');
  perform pg_temp.check_eq((d ->> 'arrivalCost')::numeric, 870000, 'dashboard juillet : arrivages reçus');
  perform pg_temp.check_eq((d ->> 'charges')::numeric, 110000, 'dashboard juillet : charges');

  d := public.shop_dashboard(shop, 'Africa/Brazzaville', false, '2026-09-10 10:00+01');
  perform pg_temp.check_eq((d ->> 'monthSales')::numeric, 854000, 'dashboard septembre : ventes du mois');
  perform pg_temp.check_eq((d ->> 'charges')::numeric, 140000, 'dashboard septembre : charges');
end $$;

-- Arrivages en cours par type
insert into public.arrivals(shop_id, code, kind, global_cost, status)
select current_setting('covi.shop')::uuid, code, kind, 1000, status
from (values ('T-1', 'supplier_order', 'draft'), ('T-2', 'supplier_order', 'in_transit'),
             ('T-3', 'balloon', 'ordered')) as v(code, kind, status);
select pg_temp.check(
  (d ->> 'arrivalsInProgress')::int = 3 and (d ->> 'ordersInProgress')::int = 2
  and (d ->> 'balloonsInProgress')::int = 1
  and (d -> 'inProgressByStatus') = '{"draft": 1, "ordered": 1, "in_transit": 1}'::jsonb,
  'dashboard : arrivages en cours par type et statut')
from (select public.shop_dashboard(current_setting('covi.shop')::uuid) as d) x;
delete from public.arrivals where code in ('T-1', 'T-2', 'T-3');

-- Rentabilité par arrivage --------------------------------------------------------------------
select pg_temp.check(
  (select jsonb_agg(jsonb_build_array(code, cost, revenue, sold_units, remaining_units,
                                      product_count, recovery_percent, remaining_to_recover)
                    order by code)
   from public.arrival_profitability(current_setting('covi.shop')::uuid))
  = '[["TEST-BAL", 250000, 630000, 46, 4, 50, 252, 0],
      ["TEST-CHN", 620000, 1004000, 62, 3, 3, 162, 0],
      ["TEST-IND", 360000, 700000, 35, 5, 1, 194, 0]]'::jsonb,
  'arrival_profitability : coût, revenu, vendu, restant, produits, % récupéré');

-- Bénéfice estimé réel (coût réparti) --------------------------------------------------------
-- Chine : 620 000 réparti au prorata de la valeur au prix initial (20×18 000 + 15×22 000 +
-- 30×12 000 = 1 050 000) ; coût des ventes = 620 000 × 1 004 000 / 1 050 000 = 592 838,10.
-- Ballon : 250 000 / 50 pièces = 5 000 ; 46 vendues = 230 000. Inde : 9 000 × 35 = 315 000.
do $$
declare
  shop uuid := current_setting('covi.shop')::uuid;
  e jsonb := public.shop_estimated_profit(shop);
begin
  perform pg_temp.check_eq((e ->> 'revenue')::numeric, 2334000, 'bénéfice estimé : ventes');
  perform pg_temp.check_eq((e ->> 'costOfGoodsSold')::numeric, 1137838.10, 'bénéfice estimé : coût des ventes');
  perform pg_temp.check_eq((e ->> 'grossProfit')::numeric, 1196161.90, 'bénéfice estimé : marge');
  perform pg_temp.check_eq((e ->> 'charges')::numeric, 380000, 'bénéfice estimé : charges');
  perform pg_temp.check_eq((e ->> 'netProfit')::numeric, 816161.90, 'bénéfice estimé : net');
  perform pg_temp.check_eq((e ->> 'unsoldStockCost')::numeric, 92161.90, 'bénéfice estimé : coût du stock restant');
  e := public.shop_estimated_profit(shop, '2026-08-01', '2026-09-01');
  perform pg_temp.check_eq((e ->> 'revenue')::numeric, 986000, 'bénéfice estimé août : ventes');
  perform pg_temp.check_eq((e ->> 'charges')::numeric, 130000, 'bénéfice estimé août : charges');
  perform pg_temp.check_eq(
    (select round(sum(unit_cost), 2) from public.arrival_cost_allocation(shop)
     where arrival_id = current_setting('covi.balloon')::uuid), 250000,
    'ballon : coût global réparti sur les 50 pièces');
end $$;

-- Ballon : 10 nouvelles pièces découvertes => 250 000 / 60 par pièce, coût des ventes réajusté.
insert into public.products(shop_id, arrival_id, name, category, initial_sale_price,
                            quantity_on_hand, is_unique_piece)
select current_setting('covi.shop')::uuid, current_setting('covi.balloon')::uuid,
       'TEST Pièce tardive ' || g, 'Lot mixte', 15000, 1, true
from generate_series(1, 10) g;
do $$
declare
  shop uuid := current_setting('covi.shop')::uuid;
begin
  perform pg_temp.check_eq(
    (select round(max(unit_cost), 2) from public.arrival_cost_allocation(shop)
     where arrival_id = current_setting('covi.balloon')::uuid), 4166.67, 'ballon : coût par pièce réajusté');
  perform pg_temp.check_eq((public.shop_estimated_profit(shop) ->> 'costOfGoodsSold')::numeric,
    1099504.76, 'bénéfice estimé : coût des ventes après réajustement du ballon');
end $$;

-- Fuseau horaire ---------------------------------------------------------------------------------
-- Ventes le 1er octobre à 00:30 et le 30 septembre à 23:59, heure de Brazzaville (UTC+1).
reset role;
insert into public.sales(shop_id, payment_method, total_amount, sold_at) values
  (current_setting('covi.shop')::uuid, 'cash', 7000, '2026-10-01 00:30 Africa/Brazzaville'),
  (current_setting('covi.shop')::uuid, 'cash', 3000, '2026-09-30 23:59 Africa/Brazzaville');
set local role authenticated;
do $$
declare
  shop uuid := current_setting('covi.shop')::uuid;
  m jsonb := public.shop_monthly_sales(shop, 3, 'Africa/Brazzaville', false, '2026-11-10 12:00+01');
  d jsonb := public.shop_dashboard(shop, 'Africa/Brazzaville', false, '2026-10-01 09:00+01');
begin
  perform pg_temp.check((m -> 'months' -> 2 ->> 'month') = '2026-10', 'fuseau : fenêtre août-octobre');
  perform pg_temp.check_eq((m -> 'months' -> 1 ->> 'amount')::numeric, 857000,
    'fuseau : 30 septembre 23:59 compte en septembre');
  perform pg_temp.check_eq((m -> 'months' -> 2 ->> 'amount')::numeric, 7000,
    'fuseau : 1er octobre 00:30 compte en octobre');
  perform pg_temp.check_eq((d ->> 'todaySales')::numeric, 7000, 'fuseau : ventes du 1er octobre');
  perform pg_temp.check_eq((d ->> 'monthSales')::numeric, 7000, 'fuseau : ventes d''octobre');
  -- En UTC, la vente de 00:30 serait (à tort pour Brazzaville) en septembre.
  m := public.shop_monthly_sales(shop, 3, 'UTC', false, '2026-11-10 12:00Z');
  perform pg_temp.check_eq((m -> 'months' -> 1 ->> 'amount')::numeric, 864000,
    'fuseau UTC : les deux ventes tombent en septembre');
end $$;

-- Données de test (is_test) ----------------------------------------------------------------------
insert into public.products(id, shop_id, name, category, initial_sale_price, quantity_on_hand, is_test)
values ('30000000-0000-0000-0000-0000000000c9', current_setting('covi.shop')::uuid, 'TEST simulé',
        'Simulation', 5000, 2, true);
select public.record_sale(current_setting('covi.shop')::uuid, '30000000-0000-0000-0000-0000000000c9',
                          1, 5000, 'cash', gen_random_uuid());
do $$
declare
  shop uuid := current_setting('covi.shop')::uuid;
begin
  perform pg_temp.check_eq(
    (public.shop_dashboard(shop, p_include_test => true) ->> 'monthSales')::numeric
    - (public.shop_dashboard(shop) ->> 'monthSales')::numeric, 5000,
    'is_test : vente simulée exclue par défaut, incluse sur demande');
  perform pg_temp.check_eq(
    (public.shop_dashboard(shop, p_include_test => true) ->> 'stock')::numeric
    - (public.shop_dashboard(shop) ->> 'stock')::numeric, 1, 'is_test : stock simulé exclu par défaut');
  perform pg_temp.check_eq(
    (public.shop_estimated_profit(shop, p_include_test => true) ->> 'revenueWithoutCost')::numeric,
    5000, 'produit sans arrivage : vente signalée sans coût');
  perform pg_temp.check_eq(
    (public.shop_estimated_profit(shop) ->> 'revenueWithoutCost')::numeric, 0,
    'produit sans arrivage de test exclu par défaut');
end $$;

rollback;
select 'PASS aggregates.sql' as result;
