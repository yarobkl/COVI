create or replace function public.record_sale(
  p_shop_id uuid,
  p_product_id uuid,
  p_quantity integer,
  p_sold_unit_price numeric,
  p_payment_method text,
  p_client_operation_id uuid default null
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
  if p_payment_method not in ('cash','mobile_money','card','bank_transfer','other') then
    raise exception 'Invalid payment method';
  end if;

  if p_client_operation_id is not null then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(p_shop_id::text || ':' || p_client_operation_id::text, 0)
    );
    select id into v_sale_id
      from public.sales
      where shop_id = p_shop_id and client_operation_id = p_client_operation_id;
    if v_sale_id is not null then return v_sale_id; end if;
  end if;

  select * into v_product
    from public.products
    where id = p_product_id and shop_id = p_shop_id and status = 'active'
    for update;
  if not found then raise exception 'Product unavailable'; end if;
  if v_product.is_unique_piece and p_quantity <> 1 then
    raise exception 'Unique piece quantity must be 1';
  end if;
  if v_product.quantity_on_hand < p_quantity then raise exception 'Insufficient stock'; end if;

  insert into public.sales(shop_id,payment_method,total_amount,client_operation_id)
    values(p_shop_id,p_payment_method,p_sold_unit_price*p_quantity,p_client_operation_id)
    returning id into v_sale_id;
  insert into public.sale_items(sale_id,product_id,quantity,initial_unit_price,sold_unit_price)
    values(v_sale_id,p_product_id,p_quantity,v_product.initial_sale_price,p_sold_unit_price);
  update public.products
    set quantity_on_hand = quantity_on_hand - p_quantity,
        status = case when quantity_on_hand - p_quantity = 0 then 'sold' else status end
    where id = p_product_id;
  return v_sale_id;
end;
$function$;
