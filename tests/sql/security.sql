-- Règles de sécurité des écritures (migration 20261010090000_server_side_sensitive_writes).
-- Tout se passe dans une transaction annulée à la fin : la base de test reste vierge.
\set ON_ERROR_STOP 1
begin;

-- Assertion : la requête doit échouer avec le SQLSTATE attendu.
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

create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok  %', p_label;
end $$;

-- Fixtures (rôle propriétaire) : deux utilisateurs, une boutique chacun.
insert into auth.users(id) values
  ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-00000000000b');
insert into public.shops(id, owner_id, name) values
  ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000a', 'Boutique A'),
  ('10000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b', 'Boutique B');
insert into public.arrivals(id, shop_id, code, kind, global_cost, status) values
  ('20000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a', 'CMD-A',
   'supplier_order', 100000, 'draft'),
  ('20000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-00000000000b', 'CMD-B',
   'supplier_order', 100000, 'draft');
insert into public.products(id, shop_id, arrival_id, name, initial_sale_price, quantity_on_hand)
values
  ('30000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-00000000000a',
   '20000000-0000-0000-0000-00000000000a', 'Produit A', 1000, 5),
  ('30000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-00000000000b',
   '20000000-0000-0000-0000-00000000000b', 'Produit B', 1000, 5);

-- Privilèges déclarés --------------------------------------------------------------------------
select pg_temp.check(not has_table_privilege('authenticated', 'public.sales', 'insert')
  and not has_table_privilege('authenticated', 'public.sales', 'update')
  and not has_table_privilege('authenticated', 'public.sales', 'delete')
  and has_table_privilege('authenticated', 'public.sales', 'select'),
  'authenticated : sales en lecture seule');
select pg_temp.check(not has_table_privilege('authenticated', 'public.sale_items', 'insert')
  and not has_table_privilege('authenticated', 'public.sale_items', 'update')
  and not has_table_privilege('authenticated', 'public.sale_items', 'delete')
  and has_table_privilege('authenticated', 'public.sale_items', 'select'),
  'authenticated : sale_items en lecture seule');
select pg_temp.check(
  not has_column_privilege('authenticated', 'public.products', 'quantity_on_hand', 'update')
  and not has_column_privilege('authenticated', 'public.products', 'status', 'update')
  and not has_column_privilege('authenticated', 'public.products', 'shop_id', 'update')
  and has_column_privilege('authenticated', 'public.products', 'name', 'update')
  and has_column_privilege('authenticated', 'public.products', 'arrival_id', 'update')
  and has_table_privilege('authenticated', 'public.products', 'insert'),
  'authenticated : UPDATE de products limité aux colonnes descriptives');
select pg_temp.check(not has_table_privilege('authenticated', 'public.products', 'truncate')
  and not has_table_privilege('anon', 'public.products', 'select')
  and not has_table_privilege('anon', 'public.shops', 'select'),
  'anon sans accès aux tables, pas de TRUNCATE pour authenticated');
select pg_temp.check((select p.prosecdef and p.proconfig = array['search_path=""']
                      from pg_proc p where p.oid = 'public.record_sale(uuid,uuid,integer,numeric,text,uuid)'::regprocedure),
  'record_sale : SECURITY DEFINER, search_path vide');
select pg_temp.check(
  has_function_privilege('authenticated', 'public.record_sale(uuid,uuid,integer,numeric,text,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.record_sale(uuid,uuid,integer,numeric,text,uuid)', 'execute')
  and not has_function_privilege('anon', 'public.shop_dashboard(uuid,text,boolean,timestamptz)', 'execute')
  and not has_function_privilege('authenticated', 'public.touch_updated_at()', 'execute')
  and not has_function_privilege('anon', 'public.touch_updated_at()', 'execute'),
  'droits EXECUTE des fonctions');

-- Utilisateur A connecté -----------------------------------------------------------------------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', true);
set local role authenticated;

select pg_temp.check(public.record_sale('10000000-0000-0000-0000-00000000000a',
  '30000000-0000-0000-0000-00000000000a', 1, 1500, 'cash', '40000000-0000-0000-0000-000000000001')
  is not null, 'record_sale sur sa boutique');
select pg_temp.check((select quantity_on_hand from public.products
                      where id = '30000000-0000-0000-0000-00000000000a') = 4,
  'record_sale décrémente le stock malgré la perte du droit UPDATE');

select pg_temp.expect_error($$insert into public.sales(shop_id, payment_method, total_amount)
  values ('10000000-0000-0000-0000-00000000000a', 'cash', 1)$$, '42501', 'INSERT direct dans sales refusé');
select pg_temp.expect_error($$insert into public.sale_items(sale_id, product_id, quantity,
  initial_unit_price, sold_unit_price) select id, '30000000-0000-0000-0000-00000000000a', 1, 1, 1
  from public.sales limit 1$$, '42501', 'INSERT direct dans sale_items refusé');
select pg_temp.expect_error($$update public.sales set total_amount = 0$$, '42501',
  'UPDATE direct de sales refusé');
select pg_temp.expect_error($$delete from public.sales$$, '42501', 'DELETE direct de sales refusé');
select pg_temp.expect_error($$update public.sale_items set sold_unit_price = 0$$, '42501',
  'UPDATE direct de sale_items refusé');
select pg_temp.expect_error($$delete from public.sale_items$$, '42501',
  'DELETE direct de sale_items refusé');
select pg_temp.check((select count(*) from public.sales) = 1
  and (select count(*) from public.sale_items) = 1, 'lecture de ses ventes conservée');

-- record_sale sur la boutique d'un autre
select pg_temp.expect_error($$select public.record_sale('10000000-0000-0000-0000-00000000000b',
  '30000000-0000-0000-0000-00000000000b', 1, 1000, 'cash', gen_random_uuid())$$, '42501',
  'record_sale sur la boutique d''un autre refusé');
select pg_temp.expect_error($$select public.record_sale('10000000-0000-0000-0000-00000000000a',
  '30000000-0000-0000-0000-00000000000b', 1, 1000, 'cash', gen_random_uuid())$$, 'P0001',
  'record_sale avec le produit d''une autre boutique refusé');
select pg_temp.expect_error($$select public.record_sale('10000000-0000-0000-0000-00000000000a',
  '30000000-0000-0000-0000-00000000000a', null, 1000, 'cash', gen_random_uuid())$$, 'P0001',
  'record_sale avec quantité NULL refusé');

-- Stock et statut non modifiables directement
select pg_temp.expect_error($$update public.products set quantity_on_hand = 99
  where id = '30000000-0000-0000-0000-00000000000a'$$, '42501', 'UPDATE de quantity_on_hand refusé');
select pg_temp.expect_error($$update public.products set status = 'archived'
  where id = '30000000-0000-0000-0000-00000000000a'$$, '42501', 'UPDATE de status refusé');
select pg_temp.expect_error($$update public.products set is_unique_piece = true
  where id = '30000000-0000-0000-0000-00000000000a'$$, '42501', 'UPDATE de is_unique_piece refusé');
update public.products set name = 'Produit A renommé', initial_sale_price = 1200
  where id = '30000000-0000-0000-0000-00000000000a';
select pg_temp.check((select name from public.products
                      where id = '30000000-0000-0000-0000-00000000000a') = 'Produit A renommé',
  'UPDATE des colonnes descriptives autorisé');

-- Règles à la création d'un produit
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand, status)
values ('30000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-00000000000a',
        'Créé vendu', 1000, 3, 'sold');
select pg_temp.check((select status from public.products
                      where id = '30000000-0000-0000-0000-0000000000a2') = 'active',
  'statut ''active'' imposé à la création');
select pg_temp.expect_error($$insert into public.products(shop_id, name, quantity_on_hand,
  is_unique_piece) values ('10000000-0000-0000-0000-00000000000a', 'Pièce x3', 3, true)$$, '23514',
  'pièce unique avec quantité 3 refusée');
select pg_temp.expect_error($$insert into public.products(shop_id, name, quantity_on_hand,
  is_unique_piece) values ('10000000-0000-0000-0000-00000000000a', 'Pièce x0', 0, true)$$, '23514',
  'pièce unique avec quantité 0 refusée');
select pg_temp.expect_error($$insert into public.products(shop_id, name, quantity_on_hand)
  values ('10000000-0000-0000-0000-00000000000a', 'Négatif', -1)$$, '23514',
  'quantité négative refusée');
insert into public.products(shop_id, arrival_id, name, quantity_on_hand, is_unique_piece)
values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-00000000000a',
        'Pièce unique', 1, true);

-- Cohérence inter-boutiques
select pg_temp.expect_error($$insert into public.products(shop_id, arrival_id, name, quantity_on_hand)
  values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-00000000000b', 'X', 1)$$,
  '23514', 'INSERT avec l''arrivage d''une autre boutique refusé');
select pg_temp.expect_error($$update public.products set arrival_id = '20000000-0000-0000-0000-00000000000b'
  where id = '30000000-0000-0000-0000-00000000000a'$$, '23514',
  'UPDATE vers l''arrivage d''une autre boutique refusé');

-- Cycle de vie des arrivages
insert into public.arrivals(id, shop_id, code, kind, global_cost, status) values
  ('20000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-00000000000a', 'BAL-A',
   'balloon', 50000, 'received');
select pg_temp.check((select received_date from public.arrivals
                      where id = '20000000-0000-0000-0000-0000000000a2') is not null,
  'ballon créé directement reçu, date de réception renseignée');
update public.arrivals set status = 'ordered' where id = '20000000-0000-0000-0000-00000000000a';
update public.arrivals set status = 'in_transit' where id = '20000000-0000-0000-0000-00000000000a';
select pg_temp.expect_error($$update public.arrivals set status = 'draft'
  where id = '20000000-0000-0000-0000-00000000000a'$$, '23514', 'retour en arrière du statut refusé');
update public.arrivals set status = 'received', received_date = '2026-10-01'
  where id = '20000000-0000-0000-0000-00000000000a';
select pg_temp.expect_error($$update public.arrivals set status = 'in_transit'
  where id = '20000000-0000-0000-0000-00000000000a'$$, '23514', 'retour reçu → en transit refusé');
select pg_temp.expect_error($$update public.arrivals set order_date = '2026-10-05'
  where id = '20000000-0000-0000-0000-00000000000a'$$, '23514',
  'date de réception antérieure à la commande refusée');

-- Isolation des agrégats : A ne lit pas la boutique de B
select pg_temp.expect_error($$select public.shop_dashboard('10000000-0000-0000-0000-00000000000b')$$,
  '42501', 'shop_dashboard sur la boutique d''un autre refusé');
select pg_temp.check((select count(*) from public.arrival_profitability(
  '10000000-0000-0000-0000-00000000000b')) = 0, 'arrival_profitability vide pour une autre boutique');

-- Le trigger updated_at fonctionne sans droit EXECUTE sur touch_updated_at
reset role;
update public.products set updated_at = '2000-01-01' where id = '30000000-0000-0000-0000-00000000000a';
set local role authenticated;
update public.products set size = 'M' where id = '30000000-0000-0000-0000-00000000000a';
select pg_temp.check((select updated_at > '2001-01-01' from public.products
                      where id = '30000000-0000-0000-0000-00000000000a'),
  'touch_updated_at se déclenche toujours');

-- Sans session : record_sale refusé
select set_config('request.jwt.claim.sub', '', true);
select pg_temp.expect_error($$select public.record_sale('10000000-0000-0000-0000-00000000000a',
  '30000000-0000-0000-0000-00000000000a', 1, 1000, 'cash', gen_random_uuid())$$, '42501',
  'record_sale sans utilisateur refusé');

-- Rôle anon
set local role anon;
select pg_temp.expect_error($$select * from public.products$$, '42501', 'anon : lecture refusée');
select pg_temp.expect_error($$select public.record_sale('10000000-0000-0000-0000-00000000000a',
  '30000000-0000-0000-0000-00000000000a', 1, 1000, 'cash', gen_random_uuid())$$, '42501',
  'anon : record_sale refusé');

-- Contrôles réservés au propriétaire (pas atteignables par le client) -------------------------
reset role;
select pg_temp.expect_error($$insert into public.sale_items(sale_id, product_id, quantity,
  initial_unit_price, sold_unit_price) select s.id, '30000000-0000-0000-0000-00000000000b', 1, 1, 1
  from public.sales s where s.shop_id = '10000000-0000-0000-0000-00000000000a' limit 1$$, '23514',
  'ligne de vente avec le produit d''une autre boutique refusée');
select pg_temp.expect_error($$update public.arrivals set shop_id = '10000000-0000-0000-0000-00000000000b'
  where id = '20000000-0000-0000-0000-00000000000a'$$, '23514',
  'changement de boutique d''un arrivage refusé');

rollback;
select 'PASS security.sql' as result;
