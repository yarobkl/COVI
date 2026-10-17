-- COVI Restaurant — transactional server-only sessions, collaborative order and cash closure.
-- NOT DEPLOYED. No public/guest execute granted: clients will need a guarded gateway.
-- Requires sector foundation and shop integrity migrations.
alter table public.restaurant_menu_items
  add column reserved_drink_stock integer not null default 0
  check (reserved_drink_stock >= 0 and reserved_drink_stock <= drink_stock);

create table public.restaurant_table_sessions (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  table_id uuid not null,
  status text not null default 'collecting'
    check(status in ('collecting','submitted','closed_paid','closed_cancelled')),
  guest_count integer not null default 1 check(guest_count between 1 and 50),
  order_number bigint check(order_number > 0),
  order_reference text,
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  closed_at timestamptz,
  unique(shop_id,id),
  unique(shop_id,order_number),
  foreign key(shop_id,table_id) references public.restaurant_tables(shop_id,id),
  constraint session_order_state check (
    (status='collecting' and order_number is null and submitted_at is null)
    or (status<>'collecting' and order_number is not null and submitted_at is not null)
  )
);
create unique index restaurant_one_active_session_per_table
  on public.restaurant_table_sessions(shop_id,table_id)
  where status in ('collecting','submitted');
create index restaurant_sessions_by_shop on public.restaurant_table_sessions(shop_id,created_at desc);

create table public.restaurant_participants (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  session_id uuid not null,
  participant_token text not null unique
    default (replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','')),
  ready boolean not null default false,
  is_leader boolean not null default false,
  created_at timestamptz not null default now(),
  unique(shop_id,session_id,id),
  foreign key(shop_id,session_id) references public.restaurant_table_sessions(shop_id,id)
);
create unique index restaurant_only_one_leader
  on public.restaurant_participants(shop_id,session_id) where is_leader;
create index restaurant_participants_session on public.restaurant_participants(shop_id,session_id);

create table public.restaurant_session_lines (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  session_id uuid not null,
  participant_id uuid,
  menu_item_id uuid not null,
  quantity integer not null check(quantity between 1 and 100),
  unit_price_xaf bigint not null check(unit_price_xaf between 0 and 1000000000),
  status text not null default 'draft' check(status in ('draft','ordered','served')),
  created_by uuid,
  created_at timestamptz not null default now(),
  served_at timestamptz,
  unique(shop_id,id),
  foreign key(shop_id,session_id) references public.restaurant_table_sessions(shop_id,id),
  foreign key(shop_id,session_id,participant_id)
    references public.restaurant_participants(shop_id,session_id,id),
  foreign key(shop_id,menu_item_id) references public.restaurant_menu_items(shop_id,id),
  constraint source_required check(participant_id is not null or created_by is not null),
  constraint served_time_consistent check ((status='served')=(served_at is not null))
);
create unique index restaurant_one_draft_line_per_participant_item
  on public.restaurant_session_lines(shop_id,session_id,participant_id,menu_item_id)
  where status='draft' and participant_id is not null;
create index restaurant_lines_by_session on public.restaurant_session_lines(shop_id,session_id);

create table public.restaurant_order_counters (
  shop_id uuid primary key references public.shops(id),
  next_number bigint not null check(next_number >= 2)
);
create table public.restaurant_cash_payments (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  session_id uuid not null,
  operation_id uuid not null,
  amount_xaf bigint not null check(amount_xaf>0),
  method text not null check(method='cash'),
  confirmed_by uuid not null,
  confirmed_at timestamptz not null default now(),
  unique(shop_id,operation_id),
  foreign key(shop_id,session_id) references public.restaurant_table_sessions(shop_id,id)
);
create index restaurant_cash_by_session on public.restaurant_cash_payments(shop_id,session_id);
create table public.restaurant_drink_movements (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null,
  session_id uuid not null,
  line_id uuid not null,
  menu_item_id uuid not null,
  quantity_delta integer not null check(quantity_delta<0),
  stock_after integer not null check(stock_after>=0),
  created_by uuid not null,
  created_at timestamptz not null default now(),
  unique(shop_id,line_id),
  foreign key(shop_id,session_id) references public.restaurant_table_sessions(shop_id,id),
  foreign key(shop_id,line_id) references public.restaurant_session_lines(shop_id,id),
  foreign key(shop_id,menu_item_id) references public.restaurant_menu_items(shop_id,id)
);
create index restaurant_drink_movements_shop on public.restaurant_drink_movements(shop_id,created_at desc);

-- No direct writes for application users: only atomic validated owner RPCs.
do $$
declare t text;
begin
 foreach t in array array[
  'restaurant_table_sessions','restaurant_participants','restaurant_session_lines',
  'restaurant_order_counters','restaurant_cash_payments','restaurant_drink_movements'
 ] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from public, anon, authenticated',t);
  execute format('grant select on public.%I to authenticated',t);
  execute format(
   'create policy owner_reads_%I on public.%I for select to authenticated using (exists(select 1 from public.shops s where s.id=shop_id and s.owner_id=(select auth.uid()) and s.business_kind=''restaurant''))',
   t,t);
 end loop;
end $$;

create function public.restaurant_open_table(
 p_shop uuid,p_table uuid,p_guest_count integer default 1
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if auth.uid() is null or not exists (
    select 1 from public.shops where id=p_shop and owner_id=auth.uid() and business_kind='restaurant'
 ) then raise exception 'Access denied' using errcode='42501'; end if;
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
 return v_id;
end; $$;

create function public.restaurant_add_participant(p_shop uuid,p_session uuid)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_status text;
begin
 if auth.uid() is null or not exists(select 1 from public.shops
   where id=p_shop and owner_id=auth.uid() and business_kind='restaurant') then
   raise exception 'Access denied' using errcode='42501'; end if;
 select status into v_status from public.restaurant_table_sessions
 where id=p_session and shop_id=p_shop for update;
 if v_status is distinct from 'collecting' then raise exception 'Session not collecting'; end if;
 insert into public.restaurant_participants(shop_id,session_id)
 values(p_shop,p_session) returning id into v_id;
 return v_id;
end; $$;

create function public.restaurant_choose_item(
 p_shop uuid,p_session uuid,p_participant uuid,p_item uuid,p_quantity integer
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_status text; v_ready boolean; v_price bigint; v_line uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.shops
  where id=p_shop and owner_id=auth.uid() and business_kind='restaurant') then
  raise exception 'Access denied' using errcode='42501'; end if;
 if p_quantity not between 0 and 100 then raise exception 'Invalid quantity'; end if;
 select status into v_status from public.restaurant_table_sessions
  where id=p_session and shop_id=p_shop for update;
 if v_status is distinct from 'collecting' then raise exception 'Session already submitted'; end if;
 select ready into v_ready from public.restaurant_participants
  where id=p_participant and shop_id=p_shop and session_id=p_session;
 if not found then raise exception 'Participant does not belong to table'; end if;
 select price_xaf into v_price from public.restaurant_menu_items
  where id=p_item and shop_id=p_shop and available;
 if not found then raise exception 'Item unavailable'; end if;
 if p_quantity=0 then
   delete from public.restaurant_session_lines
   where shop_id=p_shop and session_id=p_session and participant_id=p_participant
     and menu_item_id=p_item and status='draft';
   update public.restaurant_participants set ready=false
    where id=p_participant and shop_id=p_shop;
   return null;
 end if;
 insert into public.restaurant_session_lines(
   shop_id,session_id,participant_id,menu_item_id,quantity,unit_price_xaf
 ) values(p_shop,p_session,p_participant,p_item,p_quantity,v_price)
 on conflict (shop_id,session_id,participant_id,menu_item_id)
 where status='draft' and participant_id is not null
 do update set quantity=excluded.quantity,unit_price_xaf=excluded.unit_price_xaf
 returning id into v_line;
 update public.restaurant_participants set ready=false where id=p_participant and shop_id=p_shop;
 return v_line;
end; $$;

create function public.restaurant_mark_ready(p_shop uuid,p_session uuid,p_participant uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare v_status text; v_leader boolean;
begin
 if auth.uid() is null or not exists(select 1 from public.shops
  where id=p_shop and owner_id=auth.uid() and business_kind='restaurant') then
  raise exception 'Access denied' using errcode='42501'; end if;
 select status into v_status from public.restaurant_table_sessions
  where id=p_session and shop_id=p_shop for update;
 if v_status is distinct from 'collecting' then raise exception 'Session already submitted'; end if;
 if not exists(select 1 from public.restaurant_participants
  where id=p_participant and shop_id=p_shop and session_id=p_session) then
  raise exception 'Participant not found'; end if;
 update public.restaurant_participants set ready=true
  where id=p_participant and shop_id=p_shop and session_id=p_session;
 if not exists(select 1 from public.restaurant_participants
  where shop_id=p_shop and session_id=p_session and is_leader) then
  update public.restaurant_participants set is_leader=true
  where id=p_participant and shop_id=p_shop and session_id=p_session;
 end if;
 select is_leader into v_leader from public.restaurant_participants
  where id=p_participant and shop_id=p_shop;
 return v_leader;
end; $$;

create function public.restaurant_submit_group(p_shop uuid,p_session uuid,p_leader uuid)
returns text language plpgsql security definer set search_path=''
as $$
declare v_status text; v_count bigint; v_number bigint; v_reference text; v_stock record;
begin
 if auth.uid() is null or not exists(select 1 from public.shops
  where id=p_shop and owner_id=auth.uid() and business_kind='restaurant') then
  raise exception 'Access denied' using errcode='42501'; end if;
 select status into v_status from public.restaurant_table_sessions
  where id=p_session and shop_id=p_shop for update;
 if v_status is distinct from 'collecting' then raise exception 'Session not collecting'; end if;
 if not exists(select 1 from public.restaurant_participants
  where id=p_leader and shop_id=p_shop and session_id=p_session
  and is_leader and ready) then
  raise exception 'Only the group leader may submit'; end if;
 if exists(select 1 from public.restaurant_participants
  where shop_id=p_shop and session_id=p_session and not ready) then
  raise exception 'Waiting for participant choices'; end if;
 select count(*) into v_count from public.restaurant_session_lines
  where shop_id=p_shop and session_id=p_session and status='draft';
 if v_count=0 then raise exception 'Empty order'; end if;
 if exists(
   select 1 from public.restaurant_session_lines l
   join public.restaurant_menu_items m on m.id=l.menu_item_id and m.shop_id=l.shop_id
   where l.shop_id=p_shop and l.session_id=p_session and l.status='draft' and not m.available
 ) then raise exception 'Some items are no longer available'; end if;
 -- Lock each drink row in deterministic order to avoid deadlocks across tables.
 for v_stock in
   select l.menu_item_id,sum(l.quantity)::integer as qty
   from public.restaurant_session_lines l
   join public.restaurant_menu_items m on m.id=l.menu_item_id and m.shop_id=l.shop_id
   where l.shop_id=p_shop and l.session_id=p_session and l.status='draft' and m.kind='drink'
   group by l.menu_item_id order by l.menu_item_id
 loop
   update public.restaurant_menu_items m
   set reserved_drink_stock=reserved_drink_stock+v_stock.qty
   where m.id=v_stock.menu_item_id and m.shop_id=p_shop and m.available
    and m.drink_stock-m.reserved_drink_stock>=v_stock.qty;
   if not found then raise exception 'Drink out of stock'; end if;
 end loop;
 insert into public.restaurant_order_counters(shop_id,next_number)
  values(p_shop,2)
  on conflict(shop_id) do update set next_number=public.restaurant_order_counters.next_number+1
  returning next_number-1 into v_number;
 v_reference:='CMD-'||case when v_number<1000000 then lpad(v_number::text,6,'0') else v_number::text end;
 update public.restaurant_session_lines set status='ordered'
  where shop_id=p_shop and session_id=p_session and status='draft';
 update public.restaurant_table_sessions set status='submitted',
  order_number=v_number,order_reference=v_reference,submitted_at=now()
  where id=p_session and shop_id=p_shop;
 return v_reference;
end; $$;

create function public.restaurant_staff_add_item(
 p_shop uuid,p_session uuid,p_item uuid,p_quantity integer
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_status text; v_kind text; v_price bigint; v_id uuid;
begin
 if auth.uid() is null or not exists(select 1 from public.shops
   where id=p_shop and owner_id=auth.uid() and business_kind='restaurant') then
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
 return v_id;
end; $$;

create function public.restaurant_mark_served(p_shop uuid,p_line uuid)
returns void language plpgsql security definer set search_path=''
as $$
declare v_session uuid; v_line record; v_after integer;
begin
 if auth.uid() is null or not exists(select 1 from public.shops
  where id=p_shop and owner_id=auth.uid() and business_kind='restaurant') then
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
end; $$;

create function public.restaurant_capture_cash(
 p_shop uuid,p_session uuid,p_amount bigint,p_operation_id uuid
) returns boolean language plpgsql security definer set search_path=''
as $$
declare v_status text; v_total bigint; v_paid bigint; v_old record; v_close boolean;
begin
 if auth.uid() is null or not exists(select 1 from public.shops
  where id=p_shop and owner_id=auth.uid() and business_kind='restaurant') then
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
 if v_close then
   update public.restaurant_table_sessions
    set status='closed_paid',closed_at=now()
    where id=p_session and shop_id=p_shop;
 end if;
 return v_close;
end; $$;

do $$
declare signature text;
begin
 foreach signature in array array[
 'public.restaurant_open_table(uuid,uuid,integer)',
 'public.restaurant_add_participant(uuid,uuid)',
 'public.restaurant_choose_item(uuid,uuid,uuid,uuid,integer)',
 'public.restaurant_mark_ready(uuid,uuid,uuid)',
 'public.restaurant_submit_group(uuid,uuid,uuid)',
 'public.restaurant_staff_add_item(uuid,uuid,uuid,integer)',
 'public.restaurant_mark_served(uuid,uuid)',
 'public.restaurant_capture_cash(uuid,uuid,bigint,uuid)'
 ] loop
  execute format('revoke all on function %s from public,anon,authenticated',signature);
  execute format('grant execute on function %s to authenticated',signature);
 end loop;
end $$;
