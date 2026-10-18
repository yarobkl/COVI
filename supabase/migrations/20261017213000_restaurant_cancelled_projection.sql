-- Employee read model: keep cancelled lines visible and explicitly marked.
-- Financial totals exclude cancelled lines in UI and all payment RPCs.
create or replace function public.restaurant_staff_room(p_shop uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_role text;v_data jsonb;
begin
 if not public.restaurant_staff_allowed(p_shop,'view_room') then
   raise exception 'Access denied' using errcode='42501'; end if;
 select coalesce((select m.staff_role from public.restaurant_staff_members m
  where m.shop_id=p_shop and m.user_id=auth.uid() and m.active),'owner')
 into v_role;
 -- Refuse truncated data; do not show misleading bills or silently partial orders.
 if (select count(*) from public.restaurant_tables where shop_id=p_shop and active)>500
    or (select count(*) from public.restaurant_table_sessions
        where shop_id=p_shop and status in ('collecting','submitted'))>500
    or (select count(*) from public.restaurant_session_lines l
        join public.restaurant_table_sessions ss on ss.id=l.session_id
           and ss.shop_id=l.shop_id
        where l.shop_id=p_shop and ss.status in ('collecting','submitted'))>5000
 then raise exception 'Room view exceeds verified limits'; end if;

 select jsonb_build_object(
  'role',v_role,
  'tables',coalesce((
    select jsonb_agg(jsonb_build_object('id',t.id,'name',t.label,'capacity',t.capacity)
      order by t.label,t.id)
    from public.restaurant_tables t where t.shop_id=p_shop and t.active
  ),'[]'::jsonb),
  'sessions',coalesce((
    select jsonb_agg(jsonb_build_object('id',ss.id,'tableId',ss.table_id,
      'state',ss.status,'orderReference',ss.order_reference,
      'guests',ss.guest_count) order by ss.created_at,ss.id)
    from public.restaurant_table_sessions ss
    where ss.shop_id=p_shop and ss.status in ('collecting','submitted')
  ),'[]'::jsonb),
  'lines',coalesce((
    select jsonb_agg(jsonb_build_object('id',l.id,'sessionId',l.session_id,
      'itemId',l.menu_item_id,'name',mi.name,'quantity',l.quantity,
      'state',l.status,'unitPriceXaf',case when v_role='kitchen' then null
      else l.unit_price_xaf end) order by l.created_at,l.id)
    from public.restaurant_session_lines l
    join public.restaurant_table_sessions ss
      on ss.shop_id=l.shop_id and ss.id=l.session_id
    join public.restaurant_menu_items mi
      on mi.shop_id=l.shop_id and mi.id=l.menu_item_id
    where l.shop_id=p_shop and ss.status in ('collecting','submitted')
      and l.status in ('draft','ordered','served','cancelled')
  ),'[]'::jsonb),
  'menu',coalesce((
    select jsonb_agg(jsonb_build_object('id',mi.id,'name',mi.name,
      'priceXaf',case when v_role='kitchen' then null else mi.price_xaf end,
      'available',mi.available,
      'kind',mi.kind) order by mi.name,mi.id)
    from public.restaurant_menu_items mi where mi.shop_id=p_shop and mi.available
  ),'[]'::jsonb),
  'payments',case when v_role='kitchen' then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('sessionId',p.session_id,
       'amountXaf',p.amount_xaf) order by p.confirmed_at,p.id)
    from public.restaurant_cash_payments p
    join public.restaurant_table_sessions ss on ss.shop_id=p.shop_id
      and ss.id=p.session_id
    where p.shop_id=p_shop and ss.status in ('collecting','submitted')
  ),'[]'::jsonb) end
 ) into v_data;
 return v_data;
end; $$;
revoke all on function public.restaurant_staff_room(uuid) from public,anon;
grant execute on function public.restaurant_staff_room(uuid) to authenticated;
