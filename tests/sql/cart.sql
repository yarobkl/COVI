-- Vente multi-articles : record_cart_sale (migration 20261010100000_record_cart_sale).
-- Transaction annulée à la fin : la base de test reste vierge.
-- La concurrence (deux sessions) est testée à part : tests/sql/cart_concurrency.sh.
\set ON_ERROR_STOP 1
begin;

-- Assertion : la requête doit échouer avec le SQLSTATE et le message attendus.
create function pg_temp.expect_error(p_sql text, p_state text, p_message text, p_label text)
returns void language plpgsql as $$
declare v_state text; v_message text; v_detail text;
begin
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate, v_message = message_text,
                            v_detail = pg_exception_detail;
    if v_state <> p_state or v_message <> p_message then
      raise exception 'FAIL %: % "%" au lieu de % "%"', p_label, v_state, v_message,
        p_state, p_message;
    end if;
    raise notice 'ok  %  [% % | %]', p_label, v_state, v_message, coalesce(v_detail, '');
    return;
  end;
  raise exception 'FAIL %: la requête aurait dû échouer (%)', p_label, p_message;
end $$;

create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok  %', p_label;
end $$;

-- Fixtures (rôle propriétaire) -----------------------------------------------------------------
insert into auth.users(id) values
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000c2');
insert into public.shops(id, owner_id, name) values
  ('10000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000c1', 'Boutique C1'),
  ('10000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000c2', 'Boutique C2');
-- Boutique C1 : p1 stock 10 (5 000), p2 stock 3 (8 000), p3 pièce unique (15 000),
-- p4 et p5 produits de test, p6 archivé (via UPDATE propriétaire), p7 stock 1.
-- Boutique C2 : q1.
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand,
                            is_unique_piece, is_test) values
  ('30000000-0000-0000-0000-0000000000c1', '10000000-0000-0000-0000-0000000000c1', 'P1', 5000, 10, false, false),
  ('30000000-0000-0000-0000-0000000000c2', '10000000-0000-0000-0000-0000000000c1', 'P2', 8000, 3, false, false),
  ('30000000-0000-0000-0000-0000000000c3', '10000000-0000-0000-0000-0000000000c1', 'P3', 15000, 1, true, false),
  ('30000000-0000-0000-0000-0000000000c4', '10000000-0000-0000-0000-0000000000c1', 'P4 test', 1000, 5, false, true),
  ('30000000-0000-0000-0000-0000000000c5', '10000000-0000-0000-0000-0000000000c1', 'P5 test', 2000, 5, false, true),
  ('30000000-0000-0000-0000-0000000000c6', '10000000-0000-0000-0000-0000000000c1', 'P6 archivé', 1000, 5, false, false),
  ('30000000-0000-0000-0000-0000000000c7', '10000000-0000-0000-0000-0000000000c1', 'P7', 3000, 1, false, false),
  ('30000000-0000-0000-0000-0000000000d1', '10000000-0000-0000-0000-0000000000c2', 'Q1', 1000, 5, false, false);
update public.products set status = 'archived' where id = '30000000-0000-0000-0000-0000000000c6';

-- Déclaration et droits --------------------------------------------------------------------------
select pg_temp.check((select p.prosecdef and p.proconfig = array['search_path=""']
                      from pg_proc p
                      where p.oid = 'public.record_cart_sale(uuid,jsonb,text,uuid)'::regprocedure),
  'record_cart_sale : SECURITY DEFINER, search_path vide');
select pg_temp.check(
  has_function_privilege('authenticated', 'public.record_cart_sale(uuid,jsonb,text,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.record_cart_sale(uuid,jsonb,text,uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.record_cart_sale(uuid,jsonb,text,uuid)', 'execute')
  and not exists (select 1 from information_schema.routine_privileges
                  where specific_name like 'record_cart_sale%' and grantee = 'PUBLIC'),
  'record_cart_sale : EXECUTE pour authenticated uniquement');
select pg_temp.check(
  has_function_privilege('authenticated', 'public.record_sale(uuid,uuid,integer,numeric,text,uuid)', 'execute'),
  'record_sale toujours disponible');

-- Sans session --------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":5000}]',
  'cash', gen_random_uuid())$$, '42501', 'Authentication required', 'sans session refusé');

-- Utilisateur C1 ------------------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', true);

-- Panier OK : 2 × P1 à 4 500 + 1 × P2 à 8 000 + P3 (pièce unique) à 14 000 = 31 000
select set_config('covi.sale1', public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c2","quantity":1,"sold_unit_price":8000},
    {"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":2,"sold_unit_price":4500},
    {"product_id":"30000000-0000-0000-0000-0000000000c3","quantity":1,"sold_unit_price":14000}]',
  'mobile_money', '40000000-0000-0000-0000-0000000000c1')::text, true);
select pg_temp.check((select total_amount = 31000 and payment_method = 'mobile_money'
                        and not is_test and client_operation_id = '40000000-0000-0000-0000-0000000000c1'
                      from public.sales where id = current_setting('covi.sale1')::uuid),
  'panier : une vente, total = somme des lignes (31 000), moyen de paiement, is_test faux');
select pg_temp.check((select count(*) = 3
                        and sum(quantity * sold_unit_price) = 31000
                        and bool_and(case product_id
                          when '30000000-0000-0000-0000-0000000000c1' then quantity = 2 and sold_unit_price = 4500 and initial_unit_price = 5000
                          when '30000000-0000-0000-0000-0000000000c2' then quantity = 1 and sold_unit_price = 8000 and initial_unit_price = 8000
                          when '30000000-0000-0000-0000-0000000000c3' then quantity = 1 and sold_unit_price = 14000 and initial_unit_price = 15000
                          else false end)
                      from public.sale_items where sale_id = current_setting('covi.sale1')::uuid),
  'panier : 3 lignes avec quantités, prix vendus et prix initiaux');
select pg_temp.check((select array_agg(quantity_on_hand || ':' || status order by name)
                      from public.products where name in ('P1', 'P2', 'P3'))
                     = array['8:active', '2:active', '0:sold'],
  'panier : stocks décrémentés, pièce unique passée en ''sold''');

-- Idempotence : même operation id → même vente, rien de re-décrémenté (même avec un autre contenu)
select pg_temp.check(public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c2","quantity":1,"sold_unit_price":8000},
    {"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":2,"sold_unit_price":4500},
    {"product_id":"30000000-0000-0000-0000-0000000000c3","quantity":1,"sold_unit_price":14000}]',
  'mobile_money', '40000000-0000-0000-0000-0000000000c1') = current_setting('covi.sale1')::uuid,
  'idempotence : même panier rejoué → même vente');
select pg_temp.check(public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":1}]',
  'cash', '40000000-0000-0000-0000-0000000000c1') = current_setting('covi.sale1')::uuid,
  'idempotence : la clé prime sur le contenu');
select pg_temp.check((select count(*) from public.sales
                      where client_operation_id = '40000000-0000-0000-0000-0000000000c1') = 1
  and (select count(*) from public.sale_items where sale_id = current_setting('covi.sale1')::uuid) = 3
  and (select array_agg(quantity_on_hand order by name) from public.products
       where name in ('P1', 'P2', 'P3')) = array[8, 2, 0],
  'idempotence : pas de double vente ni de double décrément');
-- La clé est partagée avec record_sale : une opération déjà enregistrée par l'une est reconnue
-- par l'autre.
select pg_temp.check(public.record_sale('10000000-0000-0000-0000-0000000000c1',
  '30000000-0000-0000-0000-0000000000c1', 1, 5000, 'cash', '40000000-0000-0000-0000-0000000000c1')
  = current_setting('covi.sale1')::uuid, 'idempotence partagée avec record_sale');

-- Tout ou rien : la 2e ligne échoue → aucune vente, aucun stock touché
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":5000},
    {"product_id":"30000000-0000-0000-0000-0000000000c2","quantity":3,"sold_unit_price":8000}]',
  'cash', '40000000-0000-0000-0000-0000000000c2')$$, 'P0001', 'Insufficient stock',
  'stock insuffisant sur une ligne');
select pg_temp.check((select count(*) from public.sales
                      where client_operation_id = '40000000-0000-0000-0000-0000000000c2') = 0
  and (select array_agg(quantity_on_hand order by name) from public.products
       where name in ('P1', 'P2')) = array[8, 2],
  'tout ou rien : aucune vente, stocks intacts');
-- La même clé peut resservir après un échec (rien n'a été enregistré)
select pg_temp.check(public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":5000},
    {"product_id":"30000000-0000-0000-0000-0000000000c2","quantity":2,"sold_unit_price":8000}]',
  'cash', '40000000-0000-0000-0000-0000000000c2') is not null,
  'après échec, la même clé sert au panier corrigé');
select pg_temp.check((select array_agg(quantity_on_hand || ':' || status order by name)
                      from public.products where name in ('P1', 'P2')) = array['7:active', '0:sold'],
  'panier corrigé : stocks décrémentés, produit à 0 → ''sold''');

-- Pièce unique
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c3","quantity":1,"sold_unit_price":1}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Product unavailable', 'pièce unique déjà vendue');
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand, is_unique_piece)
  values ('30000000-0000-0000-0000-0000000000c8', '10000000-0000-0000-0000-0000000000c1', 'P8 unique', 9000, 1, true);
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":5000},
    {"product_id":"30000000-0000-0000-0000-0000000000c8","quantity":2,"sold_unit_price":9000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Unique piece quantity must be 1',
  'pièce unique en quantité 2 refusée');

-- Doublon de produit
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":5000},
    {"product_id":"30000000-0000-0000-0000-0000000000C1","quantity":1,"sold_unit_price":4000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Duplicate product in cart',
  'même produit deux fois (casse différente) refusé');

-- Produit indisponible : autre boutique, archivé, inexistant
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":5000},
    {"product_id":"30000000-0000-0000-0000-0000000000d1","quantity":1,"sold_unit_price":1000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Product unavailable',
  'produit d''une autre boutique refusé');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c6","quantity":1,"sold_unit_price":1000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Product unavailable', 'produit archivé refusé');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"39999999-0000-0000-0000-000000000000","quantity":1,"sold_unit_price":1000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Product unavailable', 'produit inexistant refusé');

-- Test / réel
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c4","quantity":1,"sold_unit_price":1000},
    {"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":5000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Cannot mix test and real products',
  'panier mélangeant test et réel refusé');
select set_config('covi.sale_test', public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c4","quantity":2,"sold_unit_price":1000},
    {"product_id":"30000000-0000-0000-0000-0000000000c5","quantity":1,"sold_unit_price":2500.004}]',
  'card', gen_random_uuid())::text, true);
select pg_temp.check((select is_test and total_amount = 4500 from public.sales
                      where id = current_setting('covi.sale_test')::uuid),
  'panier 100 % test : is_test vrai, prix arrondi au centime (total 4 500)');

-- Validation du format
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '{"product_id":"30000000-0000-0000-0000-0000000000c1"}', 'cash', gen_random_uuid())$$,
  'P0001', 'Cart items must be a JSON array', 'objet au lieu d''un tableau');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  null, 'cash', gen_random_uuid())$$, 'P0001', 'Cart items must be a JSON array', 'panier NULL');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[]', 'cash', gen_random_uuid())$$, 'P0001', 'Cart must contain between 1 and 50 items',
  'panier vide');
select pg_temp.expect_error(format($f$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  %L, 'cash', gen_random_uuid())$f$,
  (select jsonb_agg(jsonb_build_object('product_id', gen_random_uuid(), 'quantity', 1,
                                       'sold_unit_price', 1))
   from generate_series(1, 51))), 'P0001', 'Cart must contain between 1 and 50 items',
  'panier de 51 lignes');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":0,"sold_unit_price":5000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Quantity must be positive', 'quantité 0');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1.5,"sold_unit_price":5000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Invalid cart item', 'quantité non entière');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":"1","sold_unit_price":5000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Invalid cart item', 'quantité en chaîne');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":-1}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Sold price cannot be negative', 'prix négatif');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Invalid cart item', 'prix manquant');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"pas-un-uuid","quantity":1,"sold_unit_price":1}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Invalid cart item', 'product_id invalide');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","qty":1,"quantity":1,"sold_unit_price":1}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Invalid cart item', 'clé inconnue');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":1e12}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Sale total too large', 'total trop grand');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":1}]',
  'cheque', gen_random_uuid())$$, 'P0001', 'Invalid payment method', 'moyen de paiement inconnu');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c1","quantity":1,"sold_unit_price":1}]',
  'cash', null)$$, 'P0001', 'Sale operation id is required', 'operation id manquant');

-- Boutique d'un autre utilisateur : refus avant toute lecture
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c2',
  '[{"product_id":"30000000-0000-0000-0000-0000000000d1","quantity":1,"sold_unit_price":1000}]',
  'cash', gen_random_uuid())$$, '42501', 'Shop not found', 'boutique d''un autre refusée');

-- Écritures directes toujours interdites
select pg_temp.expect_error($$insert into public.sales(shop_id, payment_method, total_amount)
  values ('10000000-0000-0000-0000-0000000000c1', 'cash', 1)$$, '42501',
  'permission denied for table sales', 'INSERT direct dans sales toujours refusé');

-- Bilan de la boutique C1 : 3 ventes, aucune trace des paniers refusés
select pg_temp.check((select count(*) from public.sales) = 3
  and (select count(*) from public.sale_items) = 7,
  'bilan : 3 ventes, 7 lignes (les paniers refusés n''ont rien laissé)');

-- Utilisateur C2 : ne voit rien de C1, et ne peut pas vendre les produits de C1
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c2', true);
select pg_temp.check((select count(*) from public.sales) = 0, 'C2 ne voit pas les ventes de C1');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c1',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c7","quantity":1,"sold_unit_price":3000}]',
  'cash', gen_random_uuid())$$, '42501', 'Shop not found',
  'utilisateur non propriétaire refusé');
select pg_temp.expect_error($$select public.record_cart_sale('10000000-0000-0000-0000-0000000000c2',
  '[{"product_id":"30000000-0000-0000-0000-0000000000c7","quantity":1,"sold_unit_price":3000}]',
  'cash', gen_random_uuid())$$, 'P0001', 'Product unavailable',
  'produit de C1 dans un panier de C2 refusé');
reset role;
select pg_temp.check((select quantity_on_hand from public.products
                      where id = '30000000-0000-0000-0000-0000000000c7') = 1,
  'stock de C1 intact après les tentatives de C2');

rollback;
