-- COVI: DRAFT ONLY. Do not apply to the production Supabase database.
-- Dependencies (in order):
--   draft_category_stock_schema.sql
--   draft_checkout_manual_payment_schema.sql
-- This is an OWNER-ONLY confirmation for the first isolated implementation.
-- Employee permissions, QR/public order creation and reservations are NOT enabled.
--
-- Critical trust boundary: money is received OUTSIDE COVI. The signed-in shop
-- owner attests that money has been received. No Mobile Money API is used.
-- SECURITY DEFINER privileges and RLS bypass MUST be audited in an isolated DB.
begin;

create or replace function public.confirm_manual_checkout_payment(
  p_shop_id uuid,
  p_order_id uuid,
  p_operation_id uuid,
  p_cashier_first_name text,
  p_method text,
  p_external_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_actor uuid;
  v_order public.checkout_orders%rowtype;
  v_existing public.manual_payment_confirmations%rowtype;
  v_first_name text;
  v_reference text;
  v_lines jsonb;
  v_line_count integer;
  v_line_total numeric;
  v_category record;
  v_inventory record;
  v_sale_id uuid;
  v_receipt_year integer;
  v_receipt_counter bigint;
  v_receipt_number text;
  v_confirmed_at timestamptz;
begin
  v_actor := (select auth.uid());
  if v_actor is null then
    raise exception 'Authentification requise' using errcode = '28000';
  end if;
  if p_shop_id is null or p_order_id is null or p_operation_id is null then
    raise exception 'Identifiants de confirmation manquants';
  end if;

  -- Do not authorize by the freely typed first name.
  -- Current schema has owner_id, but no audited staff membership/permissions.
  if not exists (
    select 1 from public.shops s
    where s.id = p_shop_id and s.owner_id = v_actor
  ) then
    raise exception 'Vous ne pouvez pas valider les paiements de cette boutique'
      using errcode = '42501';
  end if;

  v_first_name := regexp_replace(btrim(p_cashier_first_name), '[[:space:]]+', ' ', 'g');
  v_reference := nullif(btrim(p_external_reference), '');
  if v_first_name is null
     or char_length(v_first_name) not between 1 and 60
     or v_first_name ~ '[[:cntrl:]<>0-9]' then
    raise exception 'Prénom du caissier invalide';
  end if;
  if p_method is null or p_method not in ('cash', 'mobile_money', 'other') then
    raise exception 'Moyen de paiement invalide';
  end if;
  if v_reference is not null and
     (char_length(v_reference) > 120 or v_reference ~ '[[:cntrl:]]') then
    raise exception 'Référence de paiement invalide';
  end if;

  -- Only one confirmation per order can pass the lock at a time.
  select *
    into v_order
    from public.checkout_orders o
    where o.id = p_order_id and o.shop_id = p_shop_id
    for update;
  if not found then
    raise exception 'Commande introuvable';
  end if;

  select *
    into v_existing
    from public.manual_payment_confirmations m
    where m.order_id = p_order_id and m.shop_id = p_shop_id;
  if found then
    -- An exact retry returns the SAME receipt, without modifying stock.
    if v_order.status = 'paid'
       and v_existing.operation_id = p_operation_id
       and v_existing.confirmed_by = v_actor
       and v_existing.cashier_first_name = v_first_name
       and v_existing.method = p_method
       and v_existing.external_reference is not distinct from v_reference then
      return jsonb_build_object(
        'saleId', v_existing.sale_id,
        'receiptNumber', v_existing.receipt_number,
        'confirmedAt', v_existing.confirmed_at,
        'cashierFirstName', v_existing.cashier_first_name,
        'method', v_existing.method,
        'amountXaf', v_existing.amount_xaf,
        'lines', v_existing.receipt_lines
      );
    end if;
    raise exception 'Cette commande est déjà encaissée avec une autre confirmation';
  end if;

  -- Reserving inventory requires a separate auditable reservation ledger.
  -- Reject 'reserved' until that accounting is implemented, rather than
  -- consuming another order's quantity_reserved.
  if v_order.status <> 'approved' then
    raise exception 'La commande doit être approuvée et non réservée pour être encaissée';
  end if;

  -- Monetary totals are recomputed from trusted order lines. Never trust a
  -- confirmation amount sent by the browser.
  select count(*)::integer, coalesce(sum(l.line_total_xaf), 0)
    into v_line_count, v_line_total
    from public.checkout_order_lines l
    where l.shop_id = p_shop_id and l.order_id = p_order_id;
  if v_line_count < 1 or v_line_count > 100
     or v_line_total <> v_order.amount_xaf
     or v_line_total > 9000000000000 then
    raise exception 'Le panier enregistré ne correspond pas au total de la commande';
  end if;

  -- Lock categories in normalized category_key order, matching the reception RPC.
  -- This minimizes deadlocks between simultaneous arrivals and sales.
  -- Nothing is committed if ANY category fails stock validation.
  for v_category in
    select l.category_id, sum(l.quantity)::bigint as qty
    from public.checkout_order_lines l
    join public.stock_categories c
      on c.id = l.category_id and c.shop_id = l.shop_id
    where l.shop_id = p_shop_id and l.order_id = p_order_id
    group by l.category_id, c.category_key
    order by c.category_key, l.category_id
  loop
    if v_category.qty < 1 or v_category.qty > 2147483647 then
      raise exception 'Quantité de catégorie invalide';
    end if;

    select c.quantity_on_hand, c.quantity_reserved, c.is_test
      into v_inventory
      from public.stock_categories c
      where c.id = v_category.category_id and c.shop_id = p_shop_id
      for update;
    if not found or v_inventory.is_test is distinct from v_order.is_test then
      raise exception 'Catégorie de stock indisponible pour cette commande';
    end if;
    if v_inventory.quantity_on_hand - v_inventory.quantity_reserved < v_category.qty then
      raise exception 'Stock disponible insuffisant';
    end if;
  end loop;

  -- The receipt freezes line names and prices as they appeared at confirmation.
  select jsonb_agg(
    jsonb_build_object(
      'label', c.display_name,
      'quantity', l.quantity,
      'lineTotalXaf', l.line_total_xaf
    ) order by l.id
  ) into v_lines
  from public.checkout_order_lines l
  join public.stock_categories c
    on c.id = l.category_id and c.shop_id = l.shop_id
  where l.shop_id = p_shop_id and l.order_id = p_order_id;

  v_confirmed_at := clock_timestamp();
  v_receipt_year := extract(year from v_confirmed_at at time zone 'Africa/Brazzaville')::integer;

  -- Real and test sales use separate counters and visibly different prefixes.
  insert into public.shop_receipt_counters
    (shop_id, receipt_year, is_test, last_number)
  values (p_shop_id, v_receipt_year, v_order.is_test, 1)
  on conflict (shop_id, receipt_year, is_test)
  do update set last_number = public.shop_receipt_counters.last_number + 1
  returning last_number into v_receipt_counter;
  v_receipt_number := case when v_order.is_test then 'CV-TEST-' else 'CV-' end
    || v_receipt_year::text || '-' || lpad(v_receipt_counter::text, 6, '0');

  -- Keep existing financial dashboards usable without fabricating product SKUs.
  -- Category sale lines remain in checkout_order_lines / receipt_lines, NOT
  -- in the product-specific legacy public.sale_items table.
  insert into public.sales
    (shop_id, payment_method, total_amount, sold_at, client_operation_id, is_test)
  values
    (p_shop_id, p_method, v_order.amount_xaf, v_confirmed_at,
     p_operation_id, v_order.is_test)
  returning id into v_sale_id;

  for v_category in
    select l.category_id, sum(l.quantity)::bigint as qty
    from public.checkout_order_lines l
    join public.stock_categories c
      on c.id = l.category_id and c.shop_id = l.shop_id
    where l.shop_id = p_shop_id and l.order_id = p_order_id
    group by l.category_id, c.category_key
    order by c.category_key, l.category_id
  loop
    update public.stock_categories c
       set quantity_on_hand = c.quantity_on_hand - v_category.qty::integer,
           updated_at = v_confirmed_at
     where c.id = v_category.category_id
       and c.shop_id = p_shop_id
       and c.is_test = v_order.is_test
       and c.quantity_on_hand - c.quantity_reserved >= v_category.qty;
    if not found then
      raise exception 'Le stock a changé pendant la confirmation';
    end if;

    insert into public.stock_movements
      (shop_id, category_id, movement_type, quantity_delta, sale_id, operation_id)
    values
      (p_shop_id, v_category.category_id, 'sale', -v_category.qty::integer,
       v_sale_id, p_operation_id);
  end loop;

  insert into public.manual_payment_confirmations
    (order_id, shop_id, sale_id, operation_id, confirmed_by,
     cashier_first_name, confirmed_at, method, external_reference,
     receipt_number, amount_xaf, receipt_lines)
  values
    (p_order_id, p_shop_id, v_sale_id, p_operation_id, v_actor,
     v_first_name, v_confirmed_at, p_method, v_reference,
     v_receipt_number, v_order.amount_xaf, v_lines);

  update public.checkout_orders
     set status = 'paid', updated_at = v_confirmed_at
   where id = p_order_id and shop_id = p_shop_id and status = 'approved';
  if not found then
    raise exception 'État de commande modifié simultanément';
  end if;

  return jsonb_build_object(
    'saleId', v_sale_id,
    'receiptNumber', v_receipt_number,
    'confirmedAt', v_confirmed_at,
    'cashierFirstName', v_first_name,
    'method', p_method,
    'amountXaf', v_order.amount_xaf,
    'lines', v_lines
  );
end;
$function$;

-- Supabase/PostgREST functions may be executable by PUBLIC by default.
revoke all on function public.confirm_manual_checkout_payment(
  uuid, uuid, uuid, text, text, text
) from public, anon;
grant execute on function public.confirm_manual_checkout_payment(
  uuid, uuid, uuid, text, text, text
) to authenticated;
commit;

-- RELEASE GATES (not yet met):
-- 1. Test owner-only permission, anon denial, other-shop denial, and JWT roles
--    in a disposable Postgres / Supabase environment.
-- 2. Test changed-name/amount/method retry and concurrent double clicks.
-- 3. Test two separate orders racing for the last garment, plus multiple categories.
-- 4. Test TEST counters vs real receipts, missing inventory, and complete rollback.
-- 5. Audit SECURITY DEFINER function ownership and invoker privileges.
-- 6. Add a guarded order approval/creation RPC that locks order before editing lines.
-- 7. Add employee membership/permissions before enabling employee checkout.
-- 8. Update dashboards to show category-order names in the existing sales ledger.
-- 9. Never deploy this SQL or call it in production without explicit approval.
