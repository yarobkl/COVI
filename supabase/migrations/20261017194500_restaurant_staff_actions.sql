-- COVI Restaurant: server-authorized staff actions and owner-only intervention audit.
-- Replaces existing owner-only actions without changing their signatures.
-- Staff never receive the unrestricted SELECT privileges on order/payment tables.
create or replace function public.restaurant_open_table(
 p_shop uuid,p_table uuid,p_guest_count integer default 1
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if not public.restaurant_staff_allowed(p_shop,'open_table') then
   raise exception 'Access denied' using errcode='42501'; end if;
 if p_guest_count not between 1 and 50 then raise exception 'Invalid guest count'; end if;
 -- Lock table row to serialize first scanners/terminals; no parallel session opens.
 perform 1 from public.restaurant_tables
  where id=p_table and shop_id=p_shop and active for update;
 if not found then raise exception 'Table unavailable'; end if;
 if exists(select 1 from public.restaurant_table_sessions
  where shop_id=p_shop and table_id=p_table and status in ('collecting','submitted')) then
  raise exception 'Table occupied';
 end if;
 insert into public.restaurant_table_sessions(shop_id,table_id,guest_count)
 values(p_shop,p_table,p_guest_count) returning id into v_id;
 insert into public.restaurant_staff_events(shop_id,session_id,actor_user_id,event_type)
 values(p_shop,v_id,auth.uid(),'table_opened');
 return v_id;
end; $$;

create or replace function public.restaurant_issue_group_code(p_shop uuid,p_session uuid)
returns text language plpgsql security definer set search_path=''
as $$
declare v_code text; v_status text;
begin
 if not public.restaurant_staff_allowed(p_shop,'issue_group_code') then
   raise exception 'Access denied' using errcode='42501'; end if;
 select status into v_status from public.restaurant_table_sessions
 where id=p_session and shop_id=p_shop for update;
 if v_status is distinct from 'collecting' then raise exception 'This table is not collecting choices'; end if;
 -- Eight uppercase hex characters / 32 bits; Turnstile and server action rate limiting
 -- are required at the public gateway. The code is not a password or a QR replacement.
 v_code:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 insert into public.restaurant_group_admissions(shop_id,session_id,secret_digest,expires_at,created_by)
 values(p_shop,p_session,encode(sha256(convert_to(v_code,'UTF8')),'hex'),
   now()+interval '3 hours',auth.uid())
 on conflict(shop_id,session_id) do update set
 secret_digest=excluded.secret_digest,expires_at=excluded.expires_at,
 created_by=excluded.created_by,updated_at=now();
 insert into public.restaurant_staff_events(shop_id,session_id,actor_user_id,event_type)
 values(p_shop,p_session,auth.uid(),'group_code_issued');
 return v_code;
end; $$;

create or replace function public.restaurant_staff_add_item(
 p_shop uuid,p_session uuid,p_item uuid,p_quantity integer
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_status text; v_kind text; v_price bigint; v_id uuid;
begin
 if not public.restaurant_staff_allowed(p_shop,'staff_add_item') then
   raise exception 'Access denied' using errcode='42501'; end if;
 if p_quantity not between 1 and 100 then raise exception 'Invalid quantity'; end if;
 select status into v_status from public.restaurant_table_sessions
  where id=p_session and shop_id=p_shop for update;
 if v_status is distinct from 'submitted' then raise exception 'Table not taking additions'; end if;
 select kind,price_xaf into v_kind,v_price from public.restaurant_menu_items
  where id=p_item and shop_id=p_shop and available for update;
 if not found then raise exception 'Item unavailable'; end if;
 if v_kind='drink' then
  update public.restaurant_menu_items
  set reserved_drink_stock=reserved_drink_stock+p_quantity
  where id=p_item and shop_id=p_shop and available and drink_stock-reserved_drink_stock>=p_quantity;
  if not found then raise exception 'Drink out of stock'; end if;
 end if;
 insert into public.restaurant_session_lines(
   shop_id,session_id,menu_item_id,quantity,unit_price_xaf,status,created_by
 ) values(p_shop,p_session,p_item,p_quantity,v_price,'ordered',auth.uid())
 returning id into v_id;
 insert into public.restaurant_staff_events(shop_id,session_id,line_id,actor_user_id,event_type,details)
 values(p_shop,p_session,v_id,auth.uid(),'line_added',
 jsonb_build_object('itemId',p_item,'quantity',p_quantity));
 return v_id;
end; $$;

create or replace function public.restaurant_mark_served(p_shop uuid,p_line uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v_session uuid; v_line record; v_after integer;
begin
 if not public.restaurant_staff_allowed(p_shop,'mark_served') then
   raise exception 'Access denied' using errcode='42501'; end if;
 select session_id into v_session from public.restaurant_session_lines
  where shop_id=p_shop and id=p_line;
 if not found then raise exception 'Line not found'; end if;
 -- Always acquire session before line row lock; same order as cash or additions.
 perform 1 from public.restaurant_table_sessions
  where id=v_session and shop_id=p_shop and status='submitted' for update;
 if not found then raise exception 'Table not active'; end if;
 select l.*,m.kind into v_line from public.restaurant_session_lines l
  join public.restaurant_menu_items m on m.id=l.menu_item_id and m.shop_id=l.shop_id
  where l.id=p_line and l.shop_id=p_shop for update of l;
 if v_line.status='served' then return; end if;
 if v_line.status<>'ordered' then raise exception 'Not an ordered line'; end if;
 if v_line.kind='drink' then
   update public.restaurant_menu_items
   set drink_stock=drink_stock-v_line.quantity,
       reserved_drink_stock=reserved_drink_stock-v_line.quantity
   where id=v_line.menu_item_id and shop_id=p_shop
      and reserved_drink_stock>=v_line.quantity and drink_stock>=v_line.quantity
   returning drink_stock into v_after;
   if not found then raise exception 'Drink stock inconsistent'; end if;
   insert into public.restaurant_drink_movements(
     shop_id,session_id,line_id,menu_item_id,quantity_delta,stock_after,created_by
   ) values(p_shop,v_session,p_line,v_line.menu_item_id,-v_line.quantity,v_after,auth.uid());
 end if;
 update public.restaurant_session_lines set status='served',served_at=now()
  where id=p_line and shop_id=p_shop;
 insert into public.restaurant_staff_events(shop_id,session_id,line_id,actor_user_id,event_type)
 values(p_shop,v_session,p_line,auth.uid(),'line_served');
end; $$;

create or replace function public.restaurant_capture_cash(
 p_shop uuid,p_session uuid,p_amount bigint,p_operation_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_status text; v_total bigint; v_paid bigint; v_old record; v_close boolean;
begin
 if not public.restaurant_staff_allowed(p_shop,'capture_cash') then
   raise exception 'Access denied' using errcode='42501'; end if;
 if p_amount is null or p_amount<=0 or p_operation_id is null then
  raise exception 'Invalid payment input'; end if;
 select status into v_status from public.restaurant_table_sessions
  where id=p_session and shop_id=p_shop for update;
 if not found then raise exception 'Session not found'; end if;
 select * into v_old from public.restaurant_cash_payments
  where shop_id=p_shop and operation_id=p_operation_id;
 if found then
   if v_old.session_id<>p_session or v_old.amount_xaf<>p_amount then
     raise exception 'Operation key mismatch';
   end if;
   return v_status='closed_paid';
 end if;
 if v_status<>'submitted' then raise exception 'Table cannot be paid'; end if;
 select coalesce(sum(quantity::bigint*unit_price_xaf),0) into v_total
 from public.restaurant_session_lines where shop_id=p_shop and session_id=p_session
 and status in ('ordered','served');
 select coalesce(sum(amount_xaf),0) into v_paid from public.restaurant_cash_payments
 where shop_id=p_shop and session_id=p_session;
 if p_amount>v_total-v_paid then raise exception 'Amount exceeds remaining balance'; end if;
 v_close:=(v_paid+p_amount=v_total);
 -- At the end of the meal, every ordered item must be marked served.
 -- This also guarantees that all reserved drinks were posted to real stock movements.
 if v_close and exists(
   select 1 from public.restaurant_session_lines l
   where l.shop_id=p_shop and l.session_id=p_session and l.status='ordered'
 ) then raise exception 'Serve all ordered items before closing bill'; end if;
 -- By design only an authorized owner can attest physical cash actually received.
 -- Digital/mobile money must use verified provider callbacks in a later integration.
 insert into public.restaurant_cash_payments(
   shop_id,session_id,operation_id,amount_xaf,method,confirmed_by
 ) values(p_shop,p_session,p_operation_id,p_amount,'cash',auth.uid());
 insert into public.restaurant_staff_events(shop_id,session_id,actor_user_id,event_type,details)
 values(p_shop,p_session,auth.uid(),'payment_confirmed',
 jsonb_build_object('amountXaf',p_amount,'operationId',p_operation_id,'closed',v_close));
 if v_close then
   update public.restaurant_table_sessions
    set status='closed_paid',closed_at=now()
    where id=p_session and shop_id=p_shop;
 end if;
 return v_close;
end; $$;


-- Narrow staff projection. Staff never receive participant tokens, group-code digests,
-- other establishments' tables, employee salaries, or historical salary records.
create function public.restaurant_staff_room(p_shop uuid)
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
      and l.status in ('draft','ordered','served')
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
