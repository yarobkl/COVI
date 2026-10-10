-- Écritures sensibles uniquement côté serveur.
--
-- Contexte : jusqu'ici le rôle `authenticated` (clé publique + JWT de l'utilisateur) pouvait
-- écrire directement dans sales, sale_items et products.quantity_on_hand/status, la RLS ne
-- vérifiant que l'appartenance à la boutique. Un client modifié pouvait donc fabriquer des
-- ventes, effacer l'historique ou remettre du stock. Cette migration :
--   1. fait de record_sale le seul chemin d'écriture des ventes (SECURITY DEFINER + contrôle
--      explicite du propriétaire de la boutique) ;
--   2. retire les droits d'écriture directe sur sales et sale_items (lecture conservée) ;
--   3. limite l'UPDATE de products à des colonnes descriptives (pas de stock ni de statut) ;
--   4. impose la cohérence à l'INSERT de products (statut 'active', pièce unique = 1) ;
--   5. refuse les références inter-boutiques (products.arrival_id, sale_items.product_id) ;
--   6. interdit le retour arrière du cycle de statut des arrivages ;
--   7. resserre les privilèges des rôles d'API (anon, TRUNCATE/TRIGGER/REFERENCES, fonctions).
--
-- Compatibilité avec le front en production (src/lib/covi.ts, src/lib/operations.ts) :
--   - les ventes passent déjà toutes par l'RPC record_sale ; sales/sale_items ne sont que lus ;
--   - products : INSERT direct (addProduct) sans `status`, quantité 1 pour une pièce unique ;
--     aucun UPDATE ni DELETE de products par le front ;
--   - arrivals : création en 'draft' puis avance d'une étape à la fois
--     (draft → ordered → in_transit → received) ;
--   - aucun appel anonyme aux tables : AuthGate ne lit la boutique qu'avec une session.
-- Les données de production actuelles respectent déjà toutes ces règles (vérifié en lecture :
-- aucune référence inter-boutiques, aucune pièce unique > 1, aucun arrivage reçu sans date).

-- 1. record_sale : SECURITY DEFINER, propriétaire vérifié explicitement ----------------------
-- La fonction s'exécute avec les droits de son propriétaire (postgres) : la RLS ne filtre plus
-- les lignes, d'où le contrôle explicite de p_shop_id contre auth.uid() AVANT toute lecture.
-- search_path vide : tous les objets sont qualifiés (public.*, auth.*, pg_catalog.*).
-- Signature, messages d'erreur métier et idempotence inchangés pour le front.
create or replace function public.record_sale(
  p_shop_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_sold_unit_price numeric,
  p_payment_method text,
  p_client_operation_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_product public.products%rowtype;
  v_sale_id uuid;
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_shop_id is null or not exists (
    select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_uid
  ) then
    raise exception 'Shop not found' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;
  if p_sold_unit_price is null or p_sold_unit_price < 0 then
    raise exception 'Sold price cannot be negative';
  end if;
  if p_client_operation_id is null then raise exception 'Sale operation id is required'; end if;
  if p_payment_method is null
     or p_payment_method not in ('cash','mobile_money','card','bank_transfer','other') then
    raise exception 'Invalid payment method';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_shop_id::text || ':' || p_client_operation_id::text, 0)
  );
  select s.id into v_sale_id
  from public.sales s
  where s.shop_id = p_shop_id and s.client_operation_id = p_client_operation_id;
  if v_sale_id is not null then return v_sale_id; end if;
  select * into v_product
  from public.products p
  where p.id = p_product_id and p.shop_id = p_shop_id and p.status = 'active'
  for update;
  if not found then raise exception 'Product unavailable'; end if;
  if v_product.is_unique_piece and p_quantity <> 1 then
    raise exception 'Unique piece quantity must be 1';
  end if;
  if v_product.quantity_on_hand < p_quantity then raise exception 'Insufficient stock'; end if;
  insert into public.sales(shop_id, payment_method, total_amount, client_operation_id, is_test)
    values (p_shop_id, p_payment_method, p_sold_unit_price * p_quantity, p_client_operation_id,
            v_product.is_test)
    returning id into v_sale_id;
  insert into public.sale_items(sale_id, product_id, quantity, initial_unit_price, sold_unit_price)
    values (v_sale_id, p_product_id, p_quantity, v_product.initial_sale_price, p_sold_unit_price);
  update public.products
  set quantity_on_hand = quantity_on_hand - p_quantity,
      status = case when quantity_on_hand - p_quantity = 0 then 'sold' else status end
  where id = p_product_id;
  return v_sale_id;
end;
$function$;

revoke execute on function public.record_sale(uuid, uuid, integer, numeric, text, uuid)
  from public, anon;
grant execute on function public.record_sale(uuid, uuid, integer, numeric, text, uuid)
  to authenticated;

-- create_my_shop exige déjà une session (auth.uid()) : on aligne ses droits.
revoke execute on function public.create_my_shop(text, text, text, text) from public, anon;
grant execute on function public.create_my_shop(text, text, text, text) to authenticated;

-- 2. sales et sale_items : lecture seule pour les utilisateurs ------------------------------
revoke insert, update, delete on public.sales, public.sale_items from authenticated;

-- Politiques réduites à la lecture : même si un droit d'écriture était ré-accordé par erreur,
-- la RLS refuserait l'écriture (défense en profondeur).
drop policy if exists sales_shop_member_all on public.sales;
drop policy if exists sale_items_shop_member_all on public.sale_items;
create policy sales_shop_member_select on public.sales for select to authenticated
  using (exists (
    select 1 from public.shops s where s.id = shop_id and s.owner_id = (select auth.uid())
  ));
create policy sale_items_shop_member_select on public.sale_items for select to authenticated
  using (exists (
    select 1 from public.sales v join public.shops s on s.id = v.shop_id
    where v.id = sale_id and s.owner_id = (select auth.uid())
  ));

-- 3. products : UPDATE limité aux colonnes descriptives ------------------------------------
-- quantity_on_hand et status ne changent plus que par record_sale (SECURITY DEFINER).
-- shop_id, is_unique_piece, is_test, created_at ne sont plus modifiables par le client.
revoke update on public.products from authenticated;
grant update (name, category, brand, size, initial_sale_price, image_path, arrival_id)
  on public.products to authenticated;

-- 4. products : règles imposées à la création ----------------------------------------------
-- Un produit naît toujours 'active' (le client ne peut pas créer un produit « vendu » ou
-- « archivé ») et une pièce unique naît avec exactement 1 unité. quantity_on_hand >= 0 est
-- déjà garanti par la contrainte products_quantity_on_hand_check.
create or replace function public.products_enforce_insert_rules()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  new.status := 'active';
  if new.is_unique_piece and new.quantity_on_hand is distinct from 1 then
    raise exception 'Unique piece quantity must be 1' using errcode = '23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists products_enforce_insert_rules on public.products;
create trigger products_enforce_insert_rules
  before insert on public.products
  for each row execute function public.products_enforce_insert_rules();

-- 5. Cohérence inter-boutiques ---------------------------------------------------------------
-- Les clés étrangères garantissent l'existence de la ligne référencée, pas qu'elle appartient à
-- la même boutique. Les fonctions sont SECURITY DEFINER pour voir la vraie boutique de la ligne
-- référencée, indépendamment de la RLS de l'appelant.
create or replace function public.products_check_same_shop_arrival()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.arrival_id is not null and not exists (
    select 1 from public.arrivals a where a.id = new.arrival_id and a.shop_id = new.shop_id
  ) then
    raise exception 'Arrival not found in this shop' using errcode = '23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists products_check_same_shop_arrival on public.products;
create trigger products_check_same_shop_arrival
  before insert or update of arrival_id, shop_id on public.products
  for each row execute function public.products_check_same_shop_arrival();

create or replace function public.sale_items_check_same_shop_product()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not exists (
    select 1
    from public.sales s
    join public.products p on p.shop_id = s.shop_id
    where s.id = new.sale_id and p.id = new.product_id
  ) then
    raise exception 'Product not found in the shop of this sale' using errcode = '23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists sale_items_check_same_shop_product on public.sale_items;
create trigger sale_items_check_same_shop_product
  before insert or update of sale_id, product_id on public.sale_items
  for each row execute function public.sale_items_check_same_shop_product();

-- 6. Cycle de vie des arrivages ----------------------------------------------------------------
-- Ordre : draft → ordered → in_transit → received. Règles :
--   - à la création, tout statut est accepté : un ballon acheté sur place (ou une commande déjà
--     livrée) peut être saisi directement en 'received' ;
--   - ensuite le statut ne peut qu'avancer (sauter des étapes est permis, revenir en arrière non) ;
--   - un arrivage ne change pas de boutique ;
--   - un arrivage 'received' sans date de réception reçoit la date du jour (heure de
--     Brazzaville), pour être compté dans le coût des arrivages du mois ;
--   - received_date >= order_date reste garanti par la contrainte arrivals_dates_check.
create or replace function public.arrivals_enforce_lifecycle()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_steps constant text[] := array['draft', 'ordered', 'in_transit', 'received'];
begin
  if tg_op = 'UPDATE' then
    if new.shop_id is distinct from old.shop_id then
      raise exception 'Arrival shop cannot change' using errcode = '23514';
    end if;
    if pg_catalog.array_position(v_steps, new.status)
       < pg_catalog.array_position(v_steps, old.status) then
      raise exception 'Arrival status cannot go back from % to %', old.status, new.status
        using errcode = '23514';
    end if;
  end if;
  if new.status = 'received' and new.received_date is null then
    new.received_date := (pg_catalog.now() at time zone 'Africa/Brazzaville')::date;
  end if;
  return new;
end;
$function$;

drop trigger if exists arrivals_enforce_lifecycle on public.arrivals;
create trigger arrivals_enforce_lifecycle
  before insert or update on public.arrivals
  for each row execute function public.arrivals_enforce_lifecycle();

-- 7. Privilèges des rôles d'API -----------------------------------------------------------------
-- anon n'a aucune politique RLS : ses droits sur les tables ne servaient à rien et élargissaient
-- la surface d'attaque. TRUNCATE contourne la RLS : aucun rôle d'API ne doit l'avoir.
revoke all on public.shops, public.arrivals, public.products, public.sales, public.sale_items,
  public.shop_expenses from anon;
revoke truncate, trigger, references on public.shops, public.arrivals, public.products,
  public.sales, public.sale_items, public.shop_expenses from authenticated;

-- Fonctions de trigger : jamais appelées directement par un client. Le droit EXECUTE n'est
-- vérifié qu'à la création du trigger, pas à son déclenchement : les triggers continuent de
-- fonctionner pour les écritures des utilisateurs.
revoke execute on function public.touch_updated_at() from public, anon, authenticated;
revoke execute on function public.products_enforce_insert_rules() from public, anon, authenticated;
revoke execute on function public.products_check_same_shop_arrival()
  from public, anon, authenticated;
revoke execute on function public.sale_items_check_same_shop_product()
  from public, anon, authenticated;
revoke execute on function public.arrivals_enforce_lifecycle() from public, anon, authenticated;
