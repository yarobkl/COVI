-- RETOUR ARRIÈRE n° 3 (DÉCONSEILLÉ) : écritures sensibles côté serveur
-- (20261013100000_server_side_sensitive_writes). À n'exécuter qu'APRÈS les n° 1 et 2.
-- N'EST PAS une migration. Testé par tests/sql/rollback.sql.
--
-- Ce retour arrière ROUVRE la faille corrigée par #6 : un client modifié pourra de nouveau
-- écrire directement dans sales, sale_items et le stock. À n'utiliser que si le front de main
-- était bloqué par cette migration (le banc tests/sql/production_compat.sql montre que ce n'est
-- pas le cas).
--
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -1 -f supabase/rollback/3_ecritures_sensibles_20261013.sql
--   puis : notify pgrst, 'reload schema';
--
-- Aucune donnée touchée. Non restauré volontairement (sans effet sur le front) : les droits de
-- anon sur les tables (aucune politique ne les utilisait), TRUNCATE/TRIGGER/REFERENCES pour
-- authenticated, EXECUTE de create_my_shop pour anon.

-- 1. record_sale : version de production d'avant #6 (copie exacte de
--    20261007220223_mark_sales_from_test_products.sql), SECURITY INVOKER.
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
set search_path to ''
as $function$
declare
  v_product public.products%rowtype;
  v_sale_id uuid;
begin
  if p_quantity <= 0 then raise exception 'Quantity must be positive'; end if;
  if p_sold_unit_price < 0 then raise exception 'Sold price cannot be negative'; end if;
  if p_client_operation_id is null then raise exception 'Sale operation id is required'; end if;
  if p_payment_method not in ('cash','mobile_money','card','bank_transfer','other') then
    raise exception 'Invalid payment method';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_shop_id::text || ':' || p_client_operation_id::text, 0)
  );
  select id into v_sale_id
  from public.sales
  where shop_id=p_shop_id and client_operation_id=p_client_operation_id;
  if v_sale_id is not null then return v_sale_id; end if;
  select * into v_product
  from public.products
  where id=p_product_id and shop_id=p_shop_id and status='active'
  for update;
  if not found then raise exception 'Product unavailable'; end if;
  if v_product.is_unique_piece and p_quantity <> 1 then
    raise exception 'Unique piece quantity must be 1';
  end if;
  if v_product.quantity_on_hand < p_quantity then raise exception 'Insufficient stock'; end if;
  insert into public.sales(shop_id,payment_method,total_amount,client_operation_id,is_test)
    values(p_shop_id,p_payment_method,p_sold_unit_price*p_quantity,p_client_operation_id,v_product.is_test)
    returning id into v_sale_id;
  insert into public.sale_items(sale_id,product_id,quantity,initial_unit_price,sold_unit_price)
    values(v_sale_id,p_product_id,p_quantity,v_product.initial_sale_price,p_sold_unit_price);
  update public.products
  set quantity_on_hand=quantity_on_hand-p_quantity,
      status=case when quantity_on_hand-p_quantity=0 then 'sold' else status end
  where id=p_product_id;
  return v_sale_id;
end;
$function$;

-- 2. sales et sale_items : écriture directe du propriétaire, comme avant.
grant insert, update, delete on public.sales, public.sale_items to authenticated;
drop policy if exists sales_shop_member_select on public.sales;
drop policy if exists sale_items_shop_member_select on public.sale_items;
drop policy if exists sales_shop_member_all on public.sales;
drop policy if exists sale_items_shop_member_all on public.sale_items;
create policy sales_shop_member_all on public.sales for all to authenticated using (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()))) with check (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid())));
create policy sale_items_shop_member_all on public.sale_items for all to authenticated using (exists(select 1 from public.sales v join public.shops s on s.id=v.shop_id where v.id=sale_id and s.owner_id=(select auth.uid()))) with check (exists(select 1 from public.sales v join public.shops s on s.id=v.shop_id where v.id=sale_id and s.owner_id=(select auth.uid())));

-- 3. products : UPDATE de toutes les colonnes, comme avant.
grant update on public.products to authenticated;

-- 4. Déclencheurs ajoutés par #6.
drop trigger if exists products_enforce_insert_rules on public.products;
drop trigger if exists products_check_same_shop_arrival on public.products;
drop trigger if exists sale_items_check_same_shop_product on public.sale_items;
drop trigger if exists arrivals_enforce_lifecycle on public.arrivals;
drop function if exists public.products_enforce_insert_rules();
drop function if exists public.products_check_same_shop_arrival();
drop function if exists public.sale_items_check_same_shop_product();
drop function if exists public.arrivals_enforce_lifecycle();
