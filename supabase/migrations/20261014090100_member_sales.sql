-- Caisse multi-caissiers (3/3) : ventes par caissier et lecture limitée pour les membres.
--
--   1. sales.seller_id (nullable, ventes existantes inchangées) : qui a encaissé ;
--   2. lecture pour les membres ACTIFS, jamais d'écriture directe :
--        - products de leur boutique (aucune colonne de coût dans products : les coûts sont
--          dans arrivals, qui reste réservé au propriétaire) + photos des produits ;
--        - sales / sale_items : leurs propres ventes, ou toutes celles de la boutique avec
--          can_view_shop_sales ;
--        - arrivals, shop_expenses, shops : inchangés (propriétaire seul). Le membre obtient
--          nom/ville de la boutique par my_member_shops() ;
--   3. record_sale et record_cart_sale : propriétaire OU membre actif AYANT un PIN ; nouveau
--      paramètre final facultatif p_till_session (jeton de open_till_session, propriétaire
--      seulement) qui attribue la vente au caissier de la session ; seller_id renseigné ;
--      prix minimal pour un vendeur membre :
--        round(initial_sale_price × (1 − max_discount_pct / 100)), plafonné au prix affiché ;
--      le propriétaire qui vend en son nom n'a pas de minimum. Idempotence, verrous, messages
--      existants et comportement is_test inchangés.
--
-- Les anciennes signatures (sans p_till_session) sont SUPPRIMÉES puis recréées avec le paramètre
-- en plus : garder les deux surcharges rendrait l'appel PostgREST sans p_till_session ambigu
-- (PGRST203). Les appels existants (paramètres nommés, sans p_till_session) résolvent vers la
-- nouvelle fonction grâce au défaut NULL : même comportement pour le propriétaire.
--
-- Migration non destructive et idempotente.

-- 1. Vendeur de la vente ----------------------------------------------------------------------
alter table public.sales
  add column if not exists seller_id uuid references auth.users(id) on delete set null;
create index if not exists sales_seller_idx on public.sales (seller_id, sold_at desc)
  where seller_id is not null;

-- 2. Politiques de lecture des membres -----------------------------------------------------------
-- Politiques permissives SELECT uniquement : elles s'ajoutent (OU) aux politiques propriétaires
-- existantes. Aucune politique INSERT/UPDATE/DELETE pour les membres : toute écriture directe
-- d'un membre est refusée par la RLS (INSERT) ou ne touche aucune ligne (UPDATE/DELETE).
drop policy if exists products_member_select on public.products;
create policy products_member_select on public.products for select to authenticated
  using (shop_id in (select public.member_shop_ids('view_products')));

drop policy if exists sales_member_select on public.sales;
create policy sales_member_select on public.sales for select to authenticated
  using (
    shop_id in (select public.member_shop_ids('view_shop_sales'))
    or (seller_id = (select auth.uid())
        and shop_id in (select public.member_shop_ids('view_own_sales')))
  );

drop policy if exists sale_items_member_select on public.sale_items;
create policy sale_items_member_select on public.sale_items for select to authenticated
  using (exists (
    select 1 from public.sales v
    where v.id = sale_id
      and (v.shop_id in (select public.member_shop_ids('view_shop_sales'))
           or (v.seller_id = (select auth.uid())
               and v.shop_id in (select public.member_shop_ids('view_own_sales'))))
  ));

-- Photos des produits : lecture seule pour les membres actifs (le dossier = id de la boutique).
drop policy if exists "COVI members read product images" on storage.objects;
create policy "COVI members read product images" on storage.objects for select to authenticated
  using (
    bucket_id = 'covi-product-images'
    and (storage.foldername(storage.objects.name))[1] in (
      select m::text from public.member_shop_ids('view_products') as m)
  );

-- 3. Autorisation de vente commune ---------------------------------------------------------------
-- Étape 1, AVANT toute lecture : session, puis propriétaire ou membre actif. Renvoie true pour le
-- propriétaire. Lève 'Authentication required' / 'Shop not found' (42501).
create or replace function public.assert_can_sell(p_shop_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_shop_id is null then
    raise exception 'Shop not found' using errcode = '42501';
  end if;
  if exists (select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_uid) then
    return true;
  end if;
  if exists (select 1 from public.shop_members m
             where m.shop_id = p_shop_id and m.user_id = v_uid and m.active) then
    return false;
  end if;
  raise exception 'Shop not found' using errcode = '42501';
end;
$function$;

-- Étape 2, APRÈS le contrôle d'idempotence (un rejeu d'une vente déjà enregistrée renvoie son
-- id même si la session de caisse a été fermée entre-temps) : qui vend, avec quelle remise
-- maximale (NULL = pas de minimum).
--   - p_till_session donné : l'appelant doit être le propriétaire (sinon 'Till session invalid')
--     et le jeton valide pour cette boutique → vendeur = membre de la session ;
--   - sinon propriétaire → vendeur = lui-même, sans minimum ;
--   - sinon membre actif : PIN défini obligatoire ('PIN required', 42501).
create or replace function public.sale_seller(
  p_shop_id uuid,
  p_till_session text,
  out seller_id uuid,
  out max_discount_pct numeric
)
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_is_owner boolean;
  v_member public.shop_members%rowtype;
begin
  v_is_owner := exists (
    select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_uid);
  if p_till_session is not null then
    if not v_is_owner then
      raise exception 'Till session invalid' using errcode = '42501';
    end if;
    v_member := public.till_session_member(p_shop_id, p_till_session);
    seller_id := v_member.user_id;
    max_discount_pct := v_member.max_discount_pct;
    return;
  end if;
  if v_is_owner then
    seller_id := v_uid;
    max_discount_pct := null;
    return;
  end if;
  v_member := public.assert_active_member(p_shop_id);
  if not exists (select 1 from public.member_pins p
                 where p.member_id = v_member.id and p.pin_hash is not null) then
    raise exception 'PIN required' using errcode = '42501';
  end if;
  seller_id := v_uid;
  max_discount_pct := v_member.max_discount_pct;
end;
$function$;

-- Prix unitaire minimal autorisé : prix affiché moins la remise maximale, arrondi au FCFA le
-- plus proche, jamais au-dessus du prix affiché. NULL (propriétaire) = pas de minimum.
create or replace function public.min_unit_price(p_initial_price numeric, p_max_discount_pct numeric)
returns numeric
language sql
immutable
set search_path to ''
as $function$
  select case when p_max_discount_pct is null then null
    else least(p_initial_price,
               pg_catalog.round(p_initial_price * (1 - p_max_discount_pct / 100)))
  end
$function$;

drop function if exists public.record_sale(uuid, uuid, integer, numeric, text, uuid);
drop function if exists public.record_cart_sale(uuid, jsonb, text, uuid);

-- 4. record_sale --------------------------------------------------------------------------------
create or replace function public.record_sale(
  p_shop_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_sold_unit_price numeric,
  p_payment_method text,
  p_client_operation_id uuid,
  p_till_session text default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_seller record;
  v_min_price numeric;
  v_product public.products%rowtype;
  v_sale_id uuid;
begin
  -- Propriétaire ou membre actif (lève 'Authentication required' / 'Shop not found').
  perform public.assert_can_sell(p_shop_id);
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
  -- Vendeur : session de caisse, propriétaire, ou membre avec PIN.
  select * into v_seller from public.sale_seller(p_shop_id, p_till_session);
  select * into v_product
  from public.products p
  where p.id = p_product_id and p.shop_id = p_shop_id and p.status = 'active'
  for update;
  if not found then raise exception 'Product unavailable'; end if;
  if v_product.is_unique_piece and p_quantity <> 1 then
    raise exception 'Unique piece quantity must be 1';
  end if;
  if v_product.quantity_on_hand < p_quantity then raise exception 'Insufficient stock'; end if;
  v_min_price := public.min_unit_price(v_product.initial_sale_price, v_seller.max_discount_pct);
  if v_min_price is not null and p_sold_unit_price < v_min_price then
    raise exception 'Price below allowed minimum'
      using detail = pg_catalog.format('item 0: product_id %s, minimum_price=%s',
                                       p_product_id, v_min_price);
  end if;
  insert into public.sales(shop_id, payment_method, total_amount, client_operation_id, is_test,
                           seller_id)
    values (p_shop_id, p_payment_method, p_sold_unit_price * p_quantity, p_client_operation_id,
            v_product.is_test, v_seller.seller_id)
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

-- 5. record_cart_sale ---------------------------------------------------------------------------
-- Corps identique à 20261010100000_record_cart_sale.sql, sauf : autorisation par assert_can_sell
-- (propriétaire ou membre actif), vendeur résolu par sale_seller après le contrôle
-- d'idempotence, prix minimal par ligne pour un vendeur membre (après le contrôle de stock, dans
-- l'ordre du panier), seller_id renseigné. Contrat : docs/contrat-panier.md.
create or replace function public.record_cart_sale(
  p_shop_id uuid,
  p_items jsonb,
  p_payment_method text,
  p_client_operation_id uuid,
  p_till_session text default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  c_max_items constant integer := 50;
  c_max_total constant numeric := 999999999999.99;
  c_uuid_re constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_seller record;
  v_min_price numeric;
  v_count integer;
  v_item jsonb;
  v_num numeric;
  v_product_id uuid;
  v_ids uuid[] := '{}';
  v_qtys integer[] := '{}';
  v_prices numeric[] := '{}';
  v_initial_prices numeric[] := '{}';
  v_total numeric := 0;
  v_product public.products%rowtype;
  v_any_test boolean := false;
  v_any_real boolean := false;
  v_sale_id uuid;
begin
  -- Session, propriétaire ou membre actif -----------------------------------------------------
  perform public.assert_can_sell(p_shop_id);

  -- Paramètres de la vente ---------------------------------------------------------------------
  if p_client_operation_id is null then raise exception 'Sale operation id is required'; end if;
  if p_payment_method is null
     or p_payment_method not in ('cash','mobile_money','card','bank_transfer','other') then
    raise exception 'Invalid payment method';
  end if;

  -- Format du panier (aucune lecture de table) -------------------------------------------------
  if p_items is null or pg_catalog.jsonb_typeof(p_items) <> 'array' then
    raise exception 'Cart items must be a JSON array';
  end if;
  v_count := pg_catalog.jsonb_array_length(p_items);
  if v_count < 1 or v_count > c_max_items then
    raise exception 'Cart must contain between 1 and 50 items'
      using detail = pg_catalog.format('%s item(s) received', v_count);
  end if;

  for i in 0 .. v_count - 1 loop
    v_item := p_items -> i;
    if pg_catalog.jsonb_typeof(v_item) is distinct from 'object' then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: not a JSON object', i);
    end if;
    if exists (
      select 1 from pg_catalog.jsonb_object_keys(v_item) k
      where k not in ('product_id', 'quantity', 'sold_unit_price')
    ) then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format(
          'item %s: unknown key (allowed: product_id, quantity, sold_unit_price)', i);
    end if;

    -- product_id : chaîne uuid canonique
    if pg_catalog.jsonb_typeof(v_item -> 'product_id') is distinct from 'string'
       or (v_item ->> 'product_id') !~ c_uuid_re then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: product_id must be a uuid string', i);
    end if;
    v_product_id := (v_item ->> 'product_id')::uuid;
    if v_product_id = any(v_ids) then
      raise exception 'Duplicate product in cart'
        using detail = pg_catalog.format('item %s: product_id %s already in cart', i, v_product_id);
    end if;

    -- quantity : nombre entier > 0
    if pg_catalog.jsonb_typeof(v_item -> 'quantity') is distinct from 'number' then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: quantity must be a JSON number', i);
    end if;
    v_num := (v_item ->> 'quantity')::numeric;
    if v_num <= 0 then
      raise exception 'Quantity must be positive'
        using detail = pg_catalog.format('item %s: quantity %s', i, v_num);
    end if;
    if v_num <> pg_catalog.trunc(v_num) or v_num > 2147483647 then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: quantity must be an integer', i);
    end if;

    -- sold_unit_price : nombre >= 0 (arrondi au centime comme la colonne numeric(14,2))
    if pg_catalog.jsonb_typeof(v_item -> 'sold_unit_price') is distinct from 'number' then
      raise exception 'Invalid cart item'
        using detail = pg_catalog.format('item %s: sold_unit_price must be a JSON number', i);
    end if;
    v_num := pg_catalog.round((v_item ->> 'sold_unit_price')::numeric, 2);
    if v_num < 0 then
      raise exception 'Sold price cannot be negative'
        using detail = pg_catalog.format('item %s: sold_unit_price %s', i, v_num);
    end if;

    v_ids := v_ids || v_product_id;
    v_qtys := v_qtys || (v_item ->> 'quantity')::numeric::integer;
    v_prices := v_prices || v_num;
    v_total := v_total + v_num * v_qtys[i + 1];
    if v_total > c_max_total then
      raise exception 'Sale total too large';
    end if;
  end loop;

  -- Idempotence (même clé et même verrou que record_sale) --------------------------------------
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_shop_id::text || ':' || p_client_operation_id::text, 0)
  );
  select s.id into v_sale_id
  from public.sales s
  where s.shop_id = p_shop_id and s.client_operation_id = p_client_operation_id;
  if v_sale_id is not null then return v_sale_id; end if;

  -- Vendeur : session de caisse, propriétaire, ou membre avec PIN ---------------------------------
  select * into v_seller from public.sale_seller(p_shop_id, p_till_session);

  -- Verrouillage des produits dans l'ordre des id (pas d'interblocage entre paniers) -----------
  -- ORDER BY est appliqué avant FOR UPDATE : les lignes sont verrouillées une à une dans cet ordre.
  perform 1
  from public.products p
  where p.id = any(v_ids) and p.shop_id = p_shop_id
  order by p.id
  for update;

  -- Vérifications, dans l'ordre du panier (lignes verrouillées : état le plus récent) ----------
  for i in 1 .. v_count loop
    select * into v_product
    from public.products p
    where p.id = v_ids[i] and p.shop_id = p_shop_id;
    if not found or v_product.status <> 'active' then
      raise exception 'Product unavailable'
        using detail = pg_catalog.format('item %s: product_id %s', i - 1, v_ids[i]);
    end if;
    if v_product.is_unique_piece and v_qtys[i] <> 1 then
      raise exception 'Unique piece quantity must be 1'
        using detail = pg_catalog.format('item %s: product_id %s', i - 1, v_ids[i]);
    end if;
    if v_product.quantity_on_hand < v_qtys[i] then
      raise exception 'Insufficient stock'
        using detail = pg_catalog.format('item %s: product_id %s, requested %s, available %s',
                                         i - 1, v_ids[i], v_qtys[i], v_product.quantity_on_hand);
    end if;
    v_min_price := public.min_unit_price(v_product.initial_sale_price, v_seller.max_discount_pct);
    if v_min_price is not null and v_prices[i] < v_min_price then
      raise exception 'Price below allowed minimum'
        using detail = pg_catalog.format('item %s: product_id %s, minimum_price=%s',
                                         i - 1, v_ids[i], v_min_price);
    end if;
    if v_product.is_test then v_any_test := true; else v_any_real := true; end if;
    v_initial_prices := v_initial_prices || v_product.initial_sale_price;
  end loop;
  if v_any_test and v_any_real then
    raise exception 'Cannot mix test and real products';
  end if;

  -- Écritures ----------------------------------------------------------------------------------
  insert into public.sales(shop_id, payment_method, total_amount, client_operation_id, is_test,
                           seller_id)
    values (p_shop_id, p_payment_method, v_total, p_client_operation_id, v_any_test,
            v_seller.seller_id)
    returning id into v_sale_id;

  insert into public.sale_items(sale_id, product_id, quantity, initial_unit_price, sold_unit_price)
  select v_sale_id, c.product_id, c.quantity, c.initial_unit_price, c.sold_unit_price
  from unnest(v_ids, v_qtys, v_initial_prices, v_prices)
         with ordinality as c(product_id, quantity, initial_unit_price, sold_unit_price, n)
  order by c.n;

  update public.products p
  set quantity_on_hand = p.quantity_on_hand - c.quantity,
      status = case when p.quantity_on_hand - c.quantity = 0 then 'sold' else p.status end
  from unnest(v_ids, v_qtys) as c(product_id, quantity)
  where p.id = c.product_id and p.shop_id = p_shop_id;

  return v_sale_id;
end;
$function$;

-- 6. Droits EXECUTE -----------------------------------------------------------------------------
revoke execute on function public.assert_can_sell(uuid) from public, anon, authenticated;
revoke execute on function public.sale_seller(uuid, text) from public, anon, authenticated;
revoke execute on function public.min_unit_price(numeric, numeric) from public, anon;
grant execute on function public.min_unit_price(numeric, numeric) to authenticated;
revoke execute on function public.record_sale(uuid, uuid, integer, numeric, text, uuid, text)
  from public, anon;
grant execute on function public.record_sale(uuid, uuid, integer, numeric, text, uuid, text)
  to authenticated;
revoke execute on function public.record_cart_sale(uuid, jsonb, text, uuid, text)
  from public, anon, service_role;
grant execute on function public.record_cart_sale(uuid, jsonb, text, uuid, text) to authenticated;
