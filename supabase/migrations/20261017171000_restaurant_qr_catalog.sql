-- Read-only public restaurant QR lookup, deliberately disabled for anon JWT.
-- Only the server-side restaurant-qr Edge gateway has service_role access.
-- Never expose shop_id, customer data, participant/session IDs or payment records.
create function public.restaurant_qr_catalog(p_qr_token text)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
 v_data jsonb;
begin
 if p_qr_token is null or p_qr_token !~ '^[a-f0-9]{64}$' then
   return null;
 end if;

 select jsonb_build_object(
    'restaurantName', s.name,
    'tableName', t.label,
    'capacity', t.capacity,
    'tableState', case
       when active_session.status='collecting' then 'collecting'
       when active_session.status='submitted' then 'occupied'
       else 'free' end,
    'menu', coalesce((
       select jsonb_agg(
         jsonb_build_object(
           'id', item.id, 'name', item.name, 'category', item.category,
           'kind', item.kind, 'priceXaf', item.price_xaf,
           'available', case when item.kind='drink'
             then item.drink_stock > item.reserved_drink_stock
             else true end
         ) order by item.category,item.name,item.id
       )
       from public.restaurant_menu_items item
       where item.shop_id=t.shop_id and item.available
    ), '[]'::jsonb)
   ) into v_data
 from public.restaurant_tables t
 join public.shops s on s.id=t.shop_id and s.business_kind='restaurant'
 left join lateral (
   select ss.status from public.restaurant_table_sessions ss
   where ss.shop_id=t.shop_id and ss.table_id=t.id
     and ss.status in ('collecting','submitted')
   limit 1
 ) active_session on true
 where t.qr_token=p_qr_token and t.active;
 return v_data;
end;
$$;
revoke all on function public.restaurant_qr_catalog(text) from public,anon,authenticated;
grant execute on function public.restaurant_qr_catalog(text) to service_role;
comment on function public.restaurant_qr_catalog(text) is
 'Public projection via the server Edge gateway only. QR token cannot retrieve another shop or private customers.';
