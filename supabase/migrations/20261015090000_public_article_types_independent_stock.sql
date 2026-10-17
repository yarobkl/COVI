-- Assortiment de la boutique : types d'articles indépendants du stock réel.
-- Aucun changement du stock, des ventes, ni des articles TEST.
alter table public.public_order_channels
  add column article_types text[] not null default ARRAY['Pantalon', 'Chemise', 'Jean', 'T-shirt', 'Polo', 'Robe', 'Jupe', 'Short', 'Veste', 'Pull', 'Sweat', 'Ensemble', 'Chaussures', 'Sandales', 'Sac', 'Accessoire']::text[];

CREATE OR REPLACE FUNCTION public.get_public_order_channel(p_shop_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_channel public.public_order_channels%rowtype;
begin
  perform public.assert_shop_owner(p_shop_id);
  select * into v_channel from public.public_order_channels c where c.shop_id = p_shop_id;
  if not found then return null; end if;
  return pg_catalog.jsonb_build_object('token', v_channel.token, 'enabled', v_channel.enabled,
    'showCatalog', v_channel.show_catalog, 'articleTypes', v_channel.article_types, 'message', v_channel.public_message);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_public_order_catalog(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_channel public.public_order_channels%rowtype;
  v_shop public.shops%rowtype;
  v_products jsonb := '[]'::jsonb;
begin
  select * into v_channel from public.public_order_channels c
  where c.token = p_token and c.enabled;
  if not found then return null; end if;
  select * into v_shop from public.shops s where s.id = v_channel.shop_id;
  if v_channel.show_catalog then
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', p.id, 'name', p.name, 'category', p.category, 'brand', p.brand, 'size', p.size,
        'priceXaf', p.initial_sale_price,
        'maxQuantity', case when p.is_unique_piece then 1 else least(p.quantity_on_hand, 20) end)
        order by p.category nulls last, p.name, p.id), '[]'::jsonb)
      into v_products
    from (
      select * from public.products p
      where p.shop_id = v_channel.shop_id and p.status = 'active' and not p.is_test
        and p.quantity_on_hand > 0
      order by p.category nulls last, p.name, p.id
      limit 500
    ) p;
  end if;
  return pg_catalog.jsonb_build_object(
    'shopName', v_shop.name, 'city', v_shop.city, 'neighborhood', v_shop.neighborhood,
    'message', v_channel.public_message, 'showCatalog', v_channel.show_catalog,
    'articleTypes', v_channel.article_types,
    'products', v_products);
end;
$function$;

-- Modifier uniquement la liste proposée par la boutique ; la vente réelle
-- doit toujours être rapprochée du stock par un caissier avec PIN.
create or replace function public.set_public_order_article_types(
  p_shop_id uuid, p_types text[])
returns jsonb language plpgsql security definer set search_path to ''
as $fn$
declare
  v_type text;
  v_types text[] := '{}'::text[];
begin
  perform public.assert_shop_owner(p_shop_id);
  if p_types is null or cardinality(p_types) < 1 or cardinality(p_types) > 60 then
    raise exception 'Invalid article types' using errcode = '22023';
  end if;
  foreach v_type in array p_types loop
    v_type := pg_catalog.btrim(v_type);
    if v_type is null or char_length(v_type) < 1 or char_length(v_type) > 50
       or v_type ~ '[[:cntrl:]]' then
      raise exception 'Invalid article type' using errcode = '22023';
    end if;
    if not exists (
      select 1 from pg_catalog.unnest(v_types) x where lower(x) = lower(v_type)
    ) then
      v_types := array_append(v_types, v_type);
    end if;
  end loop;
  update public.public_order_channels
     set article_types = v_types
   where shop_id = p_shop_id;
  if not found then raise exception 'Public order channel not found' using errcode = '22023'; end if;
  perform public.shop_audit(p_shop_id,'public_article_types_updated',null,
    pg_catalog.jsonb_build_object('count',cardinality(v_types)));
  return public.get_public_order_channel(p_shop_id);
end;
$fn$;

revoke execute on function public.set_public_order_article_types(uuid,text[]) from public,anon;
grant execute on function public.set_public_order_article_types(uuid,text[]) to authenticated;
