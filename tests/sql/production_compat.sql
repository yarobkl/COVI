-- Compatibilité avec le front ACTUELLEMENT en production (origin/main = ffbc1c7), une fois TOUTES
-- les migrations appliquées, AVANT le déploiement du nouveau front (les migrations passent en
-- premier). Chaque bloc reproduit un appel Supabase de main, avec les mêmes tables, colonnes,
-- filtres et paramètres nommés (PostgREST appelle les fonctions par paramètres nommés), en tant
-- que propriétaire connecté (rôle authenticated, RLS active).
--
-- Relevé des appels de main (grep de src/ hors tests) :
--   src/features/auth/CreateShopForm.tsx   rpc create_my_shop_with_location(p_name, p_city,
--                                          p_neighborhood, p_country, p_currency,
--                                          p_latitude?, p_longitude?, p_location_accuracy_m?)
--   src/features/auth/AuthGate.tsx         shops select id,name,city,country,currency
--                                          where owner_id = moi limit 1
--   src/features/settings/SettingsPage.tsx shops select …,neighborhood,latitude,longitude,
--                                          location_accuracy_m ; shops update (même liste)
--                                          returning
--   src/lib/covi.ts                        storage covi-product-images upload / signed URL /
--                                          remove ; products insert (id, shop_id, name, category,
--                                          brand, size, initial_sale_price, quantity_on_hand,
--                                          is_unique_piece, arrival_id, is_test, image_path)
--                                          returning ; products select * ; rpc record_sale (6
--                                          paramètres nommés) ; sales select avec sale_items,
--                                          products, arrivals
--   src/lib/offline.ts                     rpc record_sale (même appel, rejoué avec la même clé)
--   src/lib/operations.ts                  arrivals select/insert/update ; shop_expenses
--                                          select/insert/update/delete ; sales, products,
--                                          arrivals, shop_expenses en lecture (tableau de bord,
--                                          rentabilité, statistiques)
--   src/features/profile/*                 storage covi-profile-photos upload / signed URL /
--                                          remove (dossier = id de l'utilisateur)
-- Données fictives uniquement. Tout se passe dans une transaction annulée à la fin.
\set ON_ERROR_STOP 1
begin;

create function pg_temp.check(p_ok boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_ok is not true then raise exception 'FAIL %', p_label; end if;
  raise notice 'ok  %', p_label;
end $$;

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

\set owner '00000000-0000-0000-0000-00000000c0a1'
\set other '00000000-0000-0000-0000-00000000c0b1'
\set as_owner 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000c0a1'', true); end$$; set local role authenticated;'
\set as_other 'reset role; do $$begin perform set_config(''request.jwt.claim.sub'', ''00000000-0000-0000-0000-00000000c0b1'', true); end$$; set local role authenticated;'

insert into auth.users(id) values (:'owner'), (:'other');
insert into storage.buckets(id, name, public) values
  ('covi-product-images', 'covi-product-images', false)
  on conflict do nothing;

-- 0. Toutes les migrations du dépôt sont appliquées (le banc les rejoue toutes avant ce test).
select pg_temp.check(
  to_regprocedure('public.record_sale(uuid,uuid,integer,numeric,text,uuid,text)') is not null
  and to_regprocedure('public.record_cart_sale(uuid,jsonb,text,uuid,text)') is not null
  and to_regclass('public.owner_pins') is not null
  and to_regclass('public.shop_members') is not null,
  'état cible : toutes les migrations appliquées (record_sale à 7 paramètres, caisse, code du responsable)');

-- 1. Création de la boutique (CreateShopForm) ------------------------------------------------
:as_owner
-- Sans GPS : main passe p_latitude/p_longitude/p_location_accuracy_m à undefined (omis).
select (s).id as shop_id from (
  select public.create_my_shop_with_location(
    p_name => 'Boutique de test', p_city => 'Brazzaville', p_neighborhood => 'Poto-Poto',
    p_country => 'République du Congo', p_currency => 'XAF') s) x \gset
select pg_temp.check(:'shop_id' is not null, 'create_my_shop_with_location sans GPS (paramètres nommés de main)');
:as_other
select (s).id as other_shop from (
  select public.create_my_shop_with_location(
    p_name => 'Autre boutique', p_city => 'Pointe-Noire', p_neighborhood => 'Centre-ville',
    p_country => 'République du Congo', p_currency => 'XAF', p_latitude => -4.79,
    p_longitude => 11.86, p_location_accuracy_m => 12.5) s) x \gset
select pg_temp.check((select latitude = -4.79 and location_accuracy_m = 12.5
                      from public.shops where id = :'other_shop'),
  'create_my_shop_with_location avec GPS');

-- 2. AuthGate : la boutique possédée ------------------------------------------------------------
:as_owner
select pg_temp.check((select count(*) from (
    select id, name, city, country, currency from public.shops
    where owner_id = :'owner' limit 1) s) = 1
  and (select count(*) from public.shops) = 1,
  'AuthGate : shops select id,name,city,country,currency where owner_id = moi (et rien d''autre)');

-- 3. Ma boutique : lecture puis mise à jour (quartier, GPS) -------------------------------------
select pg_temp.check((select neighborhood = 'Poto-Poto' and latitude is null
                      from (select id, name, city, country, currency, neighborhood, latitude,
                                   longitude, location_accuracy_m
                            from public.shops where id = :'shop_id') s),
  'SettingsPage : lecture des paramètres');
with updated as (
  update public.shops
  set name = 'Boutique de test 2', country = 'République du Congo', city = 'Brazzaville',
      neighborhood = 'Moungali', latitude = -4.2634, longitude = 15.2429,
      location_accuracy_m = 8
  where id = :'shop_id'
  returning id, name, city, country, currency, neighborhood, latitude, longitude,
            location_accuracy_m)
select pg_temp.check((select count(*) = 1 and bool_and(neighborhood = 'Moungali'
                                                       and latitude = -4.2634) from updated),
  'SettingsPage : shops update (nom, ville, quartier, GPS) returning');
with updated as (
  update public.shops
  set name = 'Boutique de test 2', country = 'République du Congo', city = 'Brazzaville',
      neighborhood = null, latitude = null, longitude = null, location_accuracy_m = null
  where id = :'shop_id' returning id)
select pg_temp.check((select count(*) from updated) = 1,
  'SettingsPage : GPS et quartier effacés (null)');

-- 4. Arrivages (operations.ts) ------------------------------------------------------------------
with created as (
  insert into public.arrivals(shop_id, code, kind, origin_country, supplier_name,
                              merchandise_cost, transport_cost, customs_cost, global_cost,
                              order_date, received_date, status)
  values (:'shop_id', 'CMD-COMPAT', 'supplier_order', 'Turquie', 'Fournisseur',
          100000, 20000, 5000, 125000, current_date - 10, null, 'draft')
  returning *)
select id as arrival_id from created \gset
with created as (
  insert into public.arrivals(shop_id, code, kind, origin_country, supplier_name,
                              merchandise_cost, transport_cost, customs_cost, global_cost,
                              order_date, received_date, status)
  values (:'shop_id', 'BAL-COMPAT', 'balloon', 'Chine', null, 0, 0, 0, 90000, null, null,
          'draft')
  returning *)
select id as balloon_id from created \gset
select pg_temp.check(:'arrival_id' is not null and :'balloon_id' is not null,
  'createArrival : insert returning (commande et ballon, en brouillon)');
-- advance() : une étape à la fois, received_date ajoutée à la réception.
with s as (update public.arrivals set status = 'ordered'
           where shop_id = :'shop_id' and id = :'arrival_id' returning *)
select pg_temp.check((select count(*) from s) = 1, 'updateArrival : draft → ordered');
with s as (update public.arrivals set status = 'in_transit'
           where shop_id = :'shop_id' and id = :'arrival_id' returning *)
select pg_temp.check((select count(*) from s) = 1, 'updateArrival : ordered → in_transit');
with s as (update public.arrivals set status = 'received', received_date = current_date
           where shop_id = :'shop_id' and id = :'arrival_id' returning *)
select pg_temp.check((select count(*) from s) = 1, 'updateArrival : in_transit → received (avec date)');
with s as (update public.arrivals set status = 'ordered'
           where shop_id = :'shop_id' and id = :'balloon_id' returning *)
select pg_temp.check((select count(*) from s) = 1, 'updateArrival : ballon draft → ordered');
select pg_temp.check((select count(*) from (select * from public.arrivals
                                           where shop_id = :'shop_id'
                                           order by created_at desc) a) = 2,
  'listArrivals : select *');

-- 5. Photos et produits (covi.ts addProduct, StockPage, ArrivalsPage) ---------------------------
select gen_random_uuid() as product_id \gset
insert into storage.objects(bucket_id, name)
values ('covi-product-images', :'shop_id' || '/' || :'product_id' || '-' || gen_random_uuid() || '.webp');
select pg_temp.check((select count(*) from storage.objects
                      where bucket_id = 'covi-product-images') = 1,
  'photo produit : upload dans le dossier de la boutique, puis lecture (URL signée)');
with created as (
  insert into public.products(id, shop_id, name, category, brand, size, initial_sale_price,
                              quantity_on_hand, is_unique_piece, arrival_id, is_test, image_path)
  values (:'product_id', :'shop_id', 'Jean slim', 'Jeans', 'Levis', '32', 15000, 4, false,
          :'arrival_id', false,
          (select name from storage.objects where bucket_id = 'covi-product-images' limit 1))
  returning *)
select pg_temp.check((select count(*) = 1 and bool_and(status = 'active') from created),
  'addProduct : insert returning (article d''un arrivage, avec photo)');
with created as (
  insert into public.products(id, shop_id, name, category, brand, size, initial_sale_price,
                              quantity_on_hand, is_unique_piece, arrival_id, is_test, image_path)
  values (gen_random_uuid(), :'shop_id', 'Veste unique', '', '', '', 18000, 1, true,
          :'balloon_id', false, null)
  returning *)
select id as veste_id from created \gset
with created as (
  insert into public.products(id, shop_id, name, category, brand, size, initial_sale_price,
                              quantity_on_hand, is_unique_piece, arrival_id, is_test, image_path)
  values (gen_random_uuid(), :'shop_id', 'Article d''exemple', '', '', '', 1000, 3, false,
          null, true, null)
  returning *)
select pg_temp.check((select count(*) from created) = 1,
  'addProduct : pièce unique (quantité 1), article d''exemple sans arrivage');
-- Échec après l'envoi de la photo : main supprime le fichier.
insert into storage.objects(bucket_id, name)
values ('covi-product-images', :'shop_id' || '/orphan.jpg');
with removed as (delete from storage.objects
                 where bucket_id = 'covi-product-images' and name = :'shop_id' || '/orphan.jpg'
                 returning 1)
select pg_temp.check((select count(*) from removed) = 1, 'photo produit : remove');
select pg_temp.check((select count(*) from (
    select * from public.products where shop_id = :'shop_id' and status = 'active'
    order by created_at desc) p) = 3,
  'listProducts : select * (stock actif)');

-- 6. Ventes : record_sale exactement comme main (6 paramètres nommés, sans p_till_session) ------
select public.record_sale(
  p_shop_id => :'shop_id', p_product_id => :'product_id', p_quantity => 2,
  p_sold_unit_price => 14000, p_payment_method => 'mobile_money',
  p_client_operation_id => '40000000-0000-0000-0000-00000000c001') as sale1 \gset
select pg_temp.check(:'sale1' is not null, 'recordSale : vente enregistrée (6 paramètres nommés)');
select pg_temp.check(public.record_sale(
  p_shop_id => :'shop_id', p_product_id => :'product_id', p_quantity => 2,
  p_sold_unit_price => 14000, p_payment_method => 'mobile_money',
  p_client_operation_id => '40000000-0000-0000-0000-00000000c001') = :'sale1',
  'file hors connexion : rejeu avec la même clé → même vente, pas de doublon');
select pg_temp.check((select quantity_on_hand from public.products where id = :'product_id') = 2,
  'stock décompté une seule fois');
select pg_temp.check(public.record_sale(
  p_shop_id => :'shop_id', p_product_id => :'veste_id', p_quantity => 1,
  p_sold_unit_price => 2000, p_payment_method => 'cash',
  p_client_operation_id => gen_random_uuid()) is not null,
  'le propriétaire vend sans prix minimal (même très bas)');
select pg_temp.check((select status from public.products where id = :'veste_id') = 'sold',
  'pièce unique vendue : statut sold');
select pg_temp.check((select bool_and(seller_id = :'owner') from public.sales
                      where shop_id = :'shop_id'),
  'ventes du front actuel : vendeur = le propriétaire (nouvelle colonne seller_id)');
-- Messages d'erreur que main traduit (saleErrors / offline.ts) : inchangés.
select pg_temp.expect_msg(format($q$select public.record_sale(p_shop_id => %L,
  p_product_id => %L, p_quantity => 5, p_sold_unit_price => 1000, p_payment_method => 'cash',
  p_client_operation_id => gen_random_uuid())$q$, :'shop_id', :'product_id'),
  'Insufficient stock', 'message inchangé : Insufficient stock');
select pg_temp.expect_msg(format($q$select public.record_sale(p_shop_id => %L,
  p_product_id => %L, p_quantity => 1, p_sold_unit_price => 1000, p_payment_method => 'cash',
  p_client_operation_id => gen_random_uuid())$q$, :'shop_id', :'veste_id'),
  'Product unavailable', 'message inchangé : Product unavailable');
select pg_temp.expect_msg(format($q$select public.record_sale(p_shop_id => %L,
  p_product_id => %L, p_quantity => 1, p_sold_unit_price => 1000, p_payment_method => 'cash',
  p_client_operation_id => null)$q$, :'shop_id', :'product_id'),
  'Sale operation id is required', 'message inchangé : Sale operation id is required');
select pg_temp.expect_msg(format($q$select public.record_sale(p_shop_id => %L,
  p_product_id => %L, p_quantity => 1, p_sold_unit_price => -1, p_payment_method => 'cash',
  p_client_operation_id => gen_random_uuid())$q$, :'shop_id', :'product_id'),
  'Sold price cannot be negative', 'message inchangé : Sold price cannot be negative');

-- 7. Lectures des ventes (listSales, tableau de bord, rentabilité, statistiques) -----------------
select pg_temp.check((select count(*) from (
    select s.id, s.sold_at, s.payment_method, s.total_amount, s.is_test, i.quantity,
           i.initial_unit_price, i.sold_unit_price, p.name, p.brand, p.arrival_id, p.image_path,
           a.code, a.kind
    from public.sales s
    join public.sale_items i on i.sale_id = s.id
    join public.products p on p.id = i.product_id
    left join public.arrivals a on a.id = p.arrival_id
    where s.shop_id = :'shop_id') v) = 2,
  'listSales : sales + sale_items + products + arrivals');
select pg_temp.check((select count(*) from public.sales
                      where shop_id = :'shop_id' and is_test = false
                        and sold_at >= current_date) = 2,
  'todaySales / dashboard : sales select total_amount');
select pg_temp.check((select count(*) from public.shop_expenses where shop_id = :'shop_id') = 0
  and (select count(*) from public.products where shop_id = :'shop_id') = 3,
  'dashboard / statistiques : products et shop_expenses en lecture');

-- 8. Charges (operations.ts) ------------------------------------------------------------------
with created as (
  insert into public.shop_expenses(shop_id, category, label, amount, expense_date, recurring)
  values (:'shop_id', 'loyer', 'Loyer', 50000, current_date, true) returning *)
select id as expense_id from created \gset
with updated as (
  update public.shop_expenses
  set category = 'loyer', label = 'Loyer octobre', amount = 55000, expense_date = current_date,
      recurring = false
  where shop_id = :'shop_id' and id = :'expense_id' returning *)
select pg_temp.check((select count(*) from updated) = 1, 'createExpense puis updateExpense');
with removed as (delete from public.shop_expenses
                 where shop_id = :'shop_id' and id = :'expense_id' returning 1)
select pg_temp.check((select count(*) from removed) = 1, 'deleteExpense');

-- 9. Photo de profil (covi-profile-photos, dossier = id de l'utilisateur) ------------------------
insert into storage.objects(bucket_id, name)
values ('covi-profile-photos', :'owner' || '/' || gen_random_uuid() || '.jpg');
select pg_temp.check((select count(*) from storage.objects
                      where bucket_id = 'covi-profile-photos') = 1,
  'photo de profil : upload puis lecture');
with removed as (delete from storage.objects where bucket_id = 'covi-profile-photos' returning 1)
select pg_temp.check((select count(*) from removed) = 1, 'photo de profil : remove');

-- 10. Cloisonnement inchangé ---------------------------------------------------------------------
:as_other
select pg_temp.check((select count(*) from public.products where shop_id = :'shop_id') = 0
  and (select count(*) from public.sales where shop_id = :'shop_id') = 0
  and (select count(*) from public.arrivals where shop_id = :'shop_id') = 0,
  'un autre propriétaire ne voit toujours rien de cette boutique');
select pg_temp.expect_msg(format($q$select public.record_sale(p_shop_id => %L,
  p_product_id => %L, p_quantity => 1, p_sold_unit_price => 1000, p_payment_method => 'cash',
  p_client_operation_id => gen_random_uuid())$q$, :'shop_id', :'product_id'),
  'Shop not found', 'un autre propriétaire ne peut pas vendre dans cette boutique');

reset role;
rollback;
