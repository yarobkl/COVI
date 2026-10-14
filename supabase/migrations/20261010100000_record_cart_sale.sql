-- Vente multi-articles (panier) : record_cart_sale.
--
-- Une vente = un panier de 1 à 50 lignes, enregistré en une seule transaction (tout ou rien).
-- Mêmes garanties que record_sale (migration 20261010090000_server_side_sensitive_writes) :
--   - SECURITY DEFINER, search_path vide, objets qualifiés ;
--   - propriétaire de la boutique vérifié explicitement (auth.uid()) AVANT toute lecture ;
--   - idempotence par (shop_id, client_operation_id), sérialisée par le même verrou consultatif
--     que record_sale : rejouer le même panier renvoie la même vente sans re-décrémenter ;
--   - produits verrouillés (FOR UPDATE) dans l'ordre de leur id : deux paniers qui partagent des
--     produits attendent l'un l'autre au lieu de s'interbloquer ;
--   - vérifications par ligne : produit actif de la boutique, pièce unique ⇒ quantité 1, stock
--     suffisant ; un panier ne mélange pas produits de test et produits réels.
-- record_sale reste inchangée (file hors connexion actuelle).
--
-- Contrat complet pour les clients : docs/contrat-panier.md.
--
-- p_items : tableau JSON [{"product_id": "<uuid>", "quantity": <entier > 0>,
--                          "sold_unit_price": <nombre >= 0>}, ...]
-- Erreurs (message stable ; DETAIL précise la ligne, index 0 dans p_items) :
--   42501 'Authentication required'          pas de session
--   42501 'Shop not found'                   boutique absente ou d'un autre utilisateur
--   P0001 'Sale operation id is required'    p_client_operation_id nul
--   P0001 'Invalid payment method'
--   P0001 'Cart items must be a JSON array'
--   P0001 'Cart must contain between 1 and 50 items'
--   P0001 'Invalid cart item'                ligne mal formée (pas un objet, clé manquante,
--                                            clé inconnue, mauvais type, uuid invalide,
--                                            quantité non entière ou hors limites)
--   P0001 'Quantity must be positive'        quantité <= 0
--   P0001 'Sold price cannot be negative'
--   P0001 'Duplicate product in cart'
--   P0001 'Sale total too large'             total > 999 999 999 999,99
--   P0001 'Product unavailable'              absent, d'une autre boutique, vendu ou archivé
--   P0001 'Unique piece quantity must be 1'
--   P0001 'Insufficient stock'
--   P0001 'Cannot mix test and real products'
create or replace function public.record_cart_sale(
  p_shop_id uuid,
  p_items jsonb,
  p_payment_method text,
  p_client_operation_id uuid
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
  v_uid uuid := auth.uid();
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
  -- Session et propriétaire --------------------------------------------------------------------
  if v_uid is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if p_shop_id is null or not exists (
    select 1 from public.shops s where s.id = p_shop_id and s.owner_id = v_uid
  ) then
    raise exception 'Shop not found' using errcode = '42501';
  end if;

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
    if v_product.is_test then v_any_test := true; else v_any_real := true; end if;
    v_initial_prices := v_initial_prices || v_product.initial_sale_price;
  end loop;
  if v_any_test and v_any_real then
    raise exception 'Cannot mix test and real products';
  end if;

  -- Écritures ----------------------------------------------------------------------------------
  insert into public.sales(shop_id, payment_method, total_amount, client_operation_id, is_test)
    values (p_shop_id, p_payment_method, v_total, p_client_operation_id, v_any_test)
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

revoke execute on function public.record_cart_sale(uuid, jsonb, text, uuid)
  from public, anon, service_role;
grant execute on function public.record_cart_sale(uuid, jsonb, text, uuid) to authenticated;
