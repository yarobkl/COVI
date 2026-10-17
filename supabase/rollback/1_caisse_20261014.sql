-- RETOUR ARRIÈRE n° 1 : caisse multi-caissiers et mode comptoir.
-- Annule 20261014090000_shop_members, 20261014090050_member_pins, 20261014090100_member_sales,
-- 20261014090200_owner_pin et 20261014090300_cashier_pin_unlock. N'EST PAS une migration (dossier supabase/rollback, ignoré par
-- `supabase db push`). Testé par tests/sql/rollback.sql.
--
-- À exécuter en UNE transaction, avec le rôle postgres (SQL Editor ou psql) :
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -1 -f supabase/rollback/1_caisse_20261014.sql
-- puis : notify pgrst, 'reload schema';
--
-- Données : rien d'antérieur au déploiement n'est touché (boutiques, produits, ventes, arrivages,
-- charges). Les ventes faites entre-temps restent, avec leur colonne sales.seller_id (nullable,
-- ignorée par le front actuel). Sont supprimées : l'équipe (shop_members), les invitations, les
-- PIN, les sessions de caisse, le code du responsable et le journal d'équipe : EXPORTEZ-LES AVANT
-- (voir docs/caisse-multi-caissiers.md, « Retour arrière »).
--
-- Après ce script, record_sale et record_cart_sale redeviennent les versions « propriétaire
-- seul » de 20261013100000 et 20261013100200 (sécurisées, compatibles avec le front de main).

-- 1. Ventes : versions propriétaire seul ------------------------------------------------------
drop function if exists public.record_sale(uuid, uuid, integer, numeric, text, uuid, text);
drop function if exists public.record_cart_sale(uuid, jsonb, text, uuid, text);

-- Copie exacte de 20261013100000_server_side_sensitive_writes.sql, section 1.
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

-- Copie exacte de 20261013100200_record_cart_sale.sql.
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

-- 2. Politiques de lecture des membres ---------------------------------------------------------
drop policy if exists products_member_select on public.products;
drop policy if exists sales_member_select on public.sales;
drop policy if exists sale_items_member_select on public.sale_items;
drop policy if exists "COVI members read product images" on storage.objects;

-- 3. Tables de l'équipe (leurs déclencheurs, index et politiques partent avec elles) -----------
-- Fonctions qui renvoient le type shop_members : avant la table.
drop function if exists public.till_session_member(uuid, text);
drop function if exists public.assert_active_member(uuid);
drop table if exists public.member_pin_unlocks;
drop table if exists public.owner_pins;
drop table if exists public.till_sessions;
drop table if exists public.member_pins;
drop table if exists public.shop_audit_log;
drop table if exists public.shop_member_invite_attempts;
drop table if exists public.shop_member_invites;
drop table if exists public.shop_members;

-- 4. Fonctions de l'équipe -------------------------------------------------------------------------
drop function if exists public.cashier_pin_unlocked(uuid);
drop function if exists public.cashier_touch_unlock(uuid);
drop function if exists public.cashier_session_id();
drop function if exists public.cashier_pin_changed();
drop function if exists public.cashier_deactivated();
drop function if exists public.leave_counter_mode(uuid, text, text);
drop function if exists public.unlock_till_session(uuid, text, text);
drop function if exists public.verify_owner_pin(uuid, text);
drop function if exists public.reset_owner_pin(uuid);
drop function if exists public.set_owner_pin(uuid, text, text);
drop function if exists public.owner_pin_status(uuid);
drop function if exists public.owner_pin_audit_failure(uuid, text, jsonb);
drop function if exists public.owner_pin_check(uuid, text);
drop function if exists public.sale_seller(uuid, text);
drop function if exists public.assert_can_sell(uuid);
drop function if exists public.min_unit_price(numeric, numeric);
drop function if exists public.close_till_session(uuid, text);
drop function if exists public.open_till_session(uuid, uuid, text);
drop function if exists public.owner_reset_member_pin(uuid);
drop function if exists public.list_shop_members(uuid);
drop function if exists public.my_member_shops();
drop function if exists public.verify_my_pin(uuid, text);
drop function if exists public.set_my_pin(uuid, text, text);
drop function if exists public.has_shop_permission(uuid, text);
drop function if exists public.member_pin_check(uuid, text);
drop function if exists public.member_pin_assert_strength(text);
drop function if exists public.shop_members_close_till_sessions();
drop function if exists public.redeem_member_invite(text);
drop function if exists public.set_member_permissions(uuid, boolean, numeric);
drop function if exists public.set_member_active(uuid, boolean);
drop function if exists public.revoke_member_invite(uuid);
drop function if exists public.list_member_invites(uuid);
drop function if exists public.create_member_invite(uuid, text, boolean, numeric);
drop function if exists public.member_invite_hash(text);
drop function if exists public.member_invite_normalize(text);
drop function if exists public.member_shop_ids(text);
drop function if exists public.shop_role(uuid);
drop function if exists public.assert_shop_owner(uuid);
drop function if exists public.shop_audit(uuid, text, text, jsonb);
drop function if exists public.shop_members_check_not_owner();

-- 5. sales.seller_id : GARDÉE (nullable, ignorée par le front actuel, garde qui a vendu).
-- Pour la retirer aussi (perte de l'attribution des ventes faites entre-temps) :
--   drop index if exists public.sales_seller_idx;
--   alter table public.sales drop column if exists seller_id;
