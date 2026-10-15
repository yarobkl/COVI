-- Corrections demandées par la boutique (commandes en ligne et caisse) :
--  1. Plus de remise maximale pour les caissiers : min_unit_price ne fixe plus aucun prix
--     minimum (la colonne max_discount_pct reste, sans effet). Les ventes, stocks et boutiques
--     existants ne sont pas modifiés.
--  2. Photos des clients illisibles : dans la règle de lecture du stockage, « name » désignait
--     le nom de la boutique (colonne de shops) au lieu du chemin du fichier. Corrigé avec
--     objects.name : seul le propriétaire de la boutique lit les photos de ses commandes.
--  3. Encaissement d'une commande dont deux lignes visent le même article du stock : les lignes
--     sont regroupées (quantités additionnées) au lieu de « Duplicate product in cart ». Même
--     article à deux prix différents : refus explicite.

create or replace function public.min_unit_price(p_initial_price numeric, p_max_discount_pct numeric)
returns numeric
language sql
immutable
set search_path to ''
as $function$
  select null::numeric
$function$;

drop policy if exists "COVI owners read order reference images" on storage.objects;
create policy "COVI owners read order reference images"
on storage.objects for select to authenticated
using (
  bucket_id = 'covi-order-references'
  and exists (
    select 1 from public.shops s
    where s.id::text = (storage.foldername(objects.name))[1]
      and s.owner_id = (select auth.uid())
  )
);

CREATE OR REPLACE FUNCTION public.confirm_public_order_payment(p_order_id uuid, p_paid_method text, p_payment_reference text, p_payment_verified boolean, p_lines jsonb, p_till_session text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  c_uuid_re constant text :=
    '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_order public.public_orders%rowtype;
  v_ref text := nullif(pg_catalog.btrim(p_payment_reference), '');
  v_items jsonb := '[]'::jsonb;
  v_line public.public_order_lines%rowtype;
  v_item jsonb;
  v_product_id uuid;
  v_price numeric;
  v_sale_id uuid;
  v_sale public.sales%rowtype;
  v_idx integer;
  v_existing jsonb;
begin
  select * into v_order from public.public_orders where id = p_order_id for update;
  if not found then raise exception 'Order not found' using errcode = '42501'; end if;
  perform public.assert_shop_owner(v_order.shop_id);
  if v_order.status = 'paid' then
    return pg_catalog.jsonb_build_object('status', 'paid', 'saleId', v_order.sale_id,
      'alreadyConfirmed', true,
      'internalReference', (select s.operation_reference from public.sales s where s.id = v_order.sale_id));
  end if;
  if v_order.status not in ('new', 'accepted') then raise exception 'Order already closed'; end if;
  if p_payment_verified is not true then raise exception 'Payment not verified'; end if;
  if p_paid_method is null or p_paid_method not in ('cash', 'mobile_money', 'card', 'bank_transfer') then
    raise exception 'Invalid payment method';
  end if;
  if char_length(coalesce(v_ref, '')) > 64 or coalesce(v_ref ~ '[[:cntrl:]]', false) then
    raise exception 'Invalid payment reference';
  end if;
  if p_lines is null or pg_catalog.jsonb_typeof(p_lines) <> 'array'
     or pg_catalog.jsonb_array_length(p_lines)
        <> (select count(*) from public.public_order_lines l where l.order_id = v_order.id) then
    raise exception 'Every order line must be confirmed';
  end if;

  for v_line in select * from public.public_order_lines l where l.order_id = v_order.id
                order by l.position loop
    select e.value into v_item from pg_catalog.jsonb_array_elements(p_lines) e
    where e.value ->> 'lineId' = v_line.id::text;
    if v_item is null
       or (v_item ->> 'productId') is null or (v_item ->> 'productId') !~ c_uuid_re
       or pg_catalog.jsonb_typeof(v_item -> 'unitPriceXaf') is distinct from 'number' then
      raise exception 'Every order line must be confirmed';
    end if;
    v_product_id := (v_item ->> 'productId')::uuid;
    v_price := (v_item ->> 'unitPriceXaf')::numeric;
    if v_line.product_id is not null and v_line.product_id <> v_product_id then
      raise exception 'Order line product mismatch';
    end if;
    if not exists (select 1 from public.products p
                   where p.id = v_product_id and p.shop_id = v_order.shop_id) then
      raise exception 'Product unavailable';
    end if;
    -- Deux lignes du client rattachées au même article du stock (« Chemise L » et « Chemise
    -- blanche » → l'article Chemise) : une seule ligne de vente, quantités additionnées.
    select (e.idx - 1)::integer, e.value into v_idx, v_existing
    from pg_catalog.jsonb_array_elements(v_items) with ordinality as e(value, idx)
    where e.value ->> 'product_id' = v_product_id::text;
    if v_existing is null then
      v_items := v_items || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object(
        'product_id', v_product_id, 'quantity', v_line.quantity, 'sold_unit_price', v_price));
    elsif (v_existing ->> 'sold_unit_price')::numeric <> v_price then
      raise exception 'Same article at different prices';
    else
      v_items := pg_catalog.jsonb_set(v_items, array[v_idx::text, 'quantity'],
        pg_catalog.to_jsonb((v_existing ->> 'quantity')::integer + v_line.quantity));
    end if;
    v_existing := null;
  end loop;

  v_sale_id := public.record_cart_sale(v_order.shop_id, v_items, p_paid_method, v_order.id,
                                       p_till_session);
  select * into v_sale from public.sales where id = v_sale_id;

  update public.public_orders
  set status = 'paid', sale_id = v_sale_id, paid_method = p_paid_method,
      payment_reference = v_ref, confirmed_at = now(), confirmed_by = auth.uid(),
      cashier_profile_id = v_sale.cashier_profile_id,
      decided_at = coalesce(decided_at, now())
  where id = v_order.id;
  update public.public_order_lines l set product_id = (e.value ->> 'productId')::uuid
  from pg_catalog.jsonb_array_elements(p_lines) e
  where l.order_id = v_order.id and e.value ->> 'lineId' = l.id::text and l.product_id is null;

  perform public.shop_audit(v_order.shop_id, 'public_order_paid', v_order.id::text,
    pg_catalog.jsonb_build_object('sale_id', v_sale_id, 'method', p_paid_method));
  return pg_catalog.jsonb_build_object('status', 'paid', 'saleId', v_sale_id,
    'alreadyConfirmed', false,
    'internalReference', v_sale.operation_reference);
end;
$function$
;
