-- Retour arrière (supabase/rollback/*.sql), appliqué dans l'ordre 1 → 2 → 3 sur la base où
-- TOUTES les migrations sont passées, puis annulé (transaction). À chaque étape : les données
-- d'avant restent, et les appels du front de main (record_sale à 6 paramètres nommés, lectures)
-- marchent toujours. Données fictives uniquement.
\set ON_ERROR_STOP 1
begin;

create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok  %', p_label;
end $$;

create function pg_temp.expect_error(p_sql text, p_state text, p_label text) returns void
language plpgsql as $$
declare v_state text; v_message text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text;
    if v_state <> p_state then
      raise exception 'FAIL %: SQLSTATE % (%) au lieu de %', p_label, v_state, v_message, p_state;
    end if;
    raise notice 'ok  %  [% %]', p_label, v_state, v_message;
    return;
  end;
  raise exception 'FAIL %: la requête aurait dû échouer (%)', p_label, p_state;
end $$;

\set sa '10000000-0000-0000-0000-0000000000d1'
\set as_pg 'reset role;'
\set as_oa 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-0000000000d1'', true); end$$; set local role authenticated;'

-- Fixtures : une boutique avec une caissière, une vente du propriétaire et une vente de la
-- caissière (session de caisse), comme après quelques jours en production.
insert into auth.users(id) values
  ('00000000-0000-0000-0000-0000000000d1'), ('00000000-0000-0000-0000-0000000000d2');
insert into public.shops(id, owner_id, name) values
  (:'sa', '00000000-0000-0000-0000-0000000000d1', 'Boutique RB');
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand) values
  ('30000000-0000-0000-0000-0000000000d1', :'sa', 'Jean', 10000, 10),
  ('30000000-0000-0000-0000-0000000000d2', :'sa', 'Robe', 8000, 10);
insert into public.shop_members(id, shop_id, user_id, display_name, max_discount_pct) values
  ('50000000-0000-0000-0000-0000000000d2', :'sa', '00000000-0000-0000-0000-0000000000d2',
   'Awa', 10);
insert into public.member_pins(member_id, pin_hash) values
  ('50000000-0000-0000-0000-0000000000d2', extensions.crypt('5937', extensions.gen_salt('bf', 4)));
:as_oa
select public.set_owner_pin(:'sa', '7391');
select (public.open_till_session(:'sa', '50000000-0000-0000-0000-0000000000d2', '5937'))
  ->> 'token' as tok \gset
select public.record_sale(:'sa', '30000000-0000-0000-0000-0000000000d1', 1, 9000, 'cash',
  '40000000-0000-0000-0000-0000000000d1', p_till_session => :'tok');
select public.record_sale(:'sa', '30000000-0000-0000-0000-0000000000d1', 1, 10000, 'card',
  '40000000-0000-0000-0000-0000000000d2');
:as_pg
select count(*) as sales_before, sum(total_amount) as total_before from public.sales \gset

-- 1. Caisse multi-caissiers et mode comptoir -------------------------------------------------------
\ir ../../supabase/rollback/1_caisse_20261014.sql
select pg_temp.check(to_regclass('public.shop_members') is null
  and to_regclass('public.member_pins') is null and to_regclass('public.till_sessions') is null
  and to_regclass('public.owner_pins') is null and to_regclass('public.shop_audit_log') is null,
  'n° 1 : tables de l''équipe supprimées');
select pg_temp.check(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('open_till_session', 'set_owner_pin',
      'leave_counter_mode', 'my_member_shops', 'sale_seller', 'shop_role', 'min_unit_price')),
  'n° 1 : fonctions de l''équipe supprimées');
select pg_temp.check(not exists (select 1 from pg_policies where policyname in (
    'products_member_select', 'sales_member_select', 'sale_items_member_select',
    'COVI members read product images')),
  'n° 1 : politiques des membres supprimées');
select pg_temp.check((select count(*) from public.sales) = :sales_before
  and (select sum(total_amount) from public.sales) = :total_before
  and (select count(*) from public.sales where seller_id is not null) = :sales_before,
  'n° 1 : ventes conservées, avec leur vendeur (sales.seller_id gardée)');
select pg_temp.check(to_regprocedure('public.record_sale(uuid,uuid,integer,numeric,text,uuid)')
                       is not null
  and to_regprocedure('public.record_sale(uuid,uuid,integer,numeric,text,uuid,text)') is null
  and to_regprocedure('public.record_cart_sale(uuid,jsonb,text,uuid)') is not null,
  'n° 1 : record_sale et record_cart_sale reviennent aux signatures d''avant la caisse');
select pg_temp.check(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')),
  'n° 1 : anon n''exécute toujours aucune fonction');
:as_oa
select pg_temp.check(public.record_sale(p_shop_id => :'sa',
  p_product_id => '30000000-0000-0000-0000-0000000000d1', p_quantity => 1,
  p_sold_unit_price => 10000, p_payment_method => 'cash',
  p_client_operation_id => '40000000-0000-0000-0000-0000000000d2') is not null
  and (select count(*) from public.sales) = :sales_before,
  'n° 1 : front de main — rejeu idempotent d''une vente existante');
select pg_temp.check(public.record_sale(p_shop_id => :'sa',
  p_product_id => '30000000-0000-0000-0000-0000000000d1', p_quantity => 1,
  p_sold_unit_price => 10000, p_payment_method => 'cash',
  p_client_operation_id => gen_random_uuid()) is not null,
  'n° 1 : front de main — nouvelle vente');
select pg_temp.check(public.record_cart_sale(:'sa',
  '[{"product_id":"30000000-0000-0000-0000-0000000000d1","quantity":1,"sold_unit_price":10000},
    {"product_id":"30000000-0000-0000-0000-0000000000d2","quantity":1,"sold_unit_price":8000}]',
  'cash', gen_random_uuid()) is not null, 'n° 1 : record_cart_sale propriétaire');
select pg_temp.expect_error($$insert into public.sales(shop_id, payment_method, total_amount)
  values ('10000000-0000-0000-0000-0000000000d1', 'cash', 1)$$, '42501',
  'n° 1 : écriture directe d''une vente toujours refusée (#6 en place)');

-- 2. Agrégats et panier ------------------------------------------------------------------------
:as_pg
\ir ../../supabase/rollback/2_agregats_panier_20261013.sql
select pg_temp.check(not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('record_cart_sale', 'shop_dashboard',
      'shop_monthly_sales', 'arrival_profitability', 'arrival_cost_allocation',
      'shop_estimated_profit')),
  'n° 2 : agrégats et record_cart_sale supprimés');
:as_oa
select pg_temp.check(public.record_sale(p_shop_id => :'sa',
  p_product_id => '30000000-0000-0000-0000-0000000000d2', p_quantity => 1,
  p_sold_unit_price => 8000, p_payment_method => 'mobile_money',
  p_client_operation_id => gen_random_uuid()) is not null,
  'n° 2 : front de main — vente');

-- 3. Écritures sensibles (déconseillé) ---------------------------------------------------------------
:as_pg
\ir ../../supabase/rollback/3_ecritures_sensibles_20261013.sql
select pg_temp.check(not exists (select 1 from pg_trigger where tgname in (
    'products_enforce_insert_rules', 'products_check_same_shop_arrival',
    'sale_items_check_same_shop_product', 'arrivals_enforce_lifecycle')),
  'n° 3 : déclencheurs de #6 supprimés');
select pg_temp.check(not (select prosecdef from pg_proc
                          where oid = 'public.record_sale(uuid,uuid,integer,numeric,text,uuid)'::regprocedure),
  'n° 3 : record_sale redevient SECURITY INVOKER (version d''avant #6)');
:as_oa
select pg_temp.check(public.record_sale(p_shop_id => :'sa',
  p_product_id => '30000000-0000-0000-0000-0000000000d2', p_quantity => 1,
  p_sold_unit_price => 8000, p_payment_method => 'cash',
  p_client_operation_id => gen_random_uuid()) is not null,
  'n° 3 : front de main — vente');
with created as (
  insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand,
                              is_unique_piece, is_test)
  values (gen_random_uuid(), :'sa', 'Chemise', 5000, 2, false, false) returning *)
select pg_temp.check((select count(*) from created) = 1, 'n° 3 : front de main — ajout au stock');
select pg_temp.check((select count(*) from public.sales) >= :sales_before + 4,
  'n° 3 : toutes les ventes sont là');

reset role;
rollback;
