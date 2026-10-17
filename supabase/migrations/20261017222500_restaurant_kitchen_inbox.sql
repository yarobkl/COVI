-- COVI Restaurant kitchen: durable, tenant-scoped signals for ordered food/drinks.
-- No browser key, guest token, customer identity or financial information exposed.
create table public.restaurant_kitchen_events (
  id bigint generated always as identity primary key,
  shop_id uuid not null,
  session_id uuid not null,
  line_id uuid not null,
  created_at timestamptz not null default now(),
  unique(shop_id,line_id),
  unique(shop_id,id),
  foreign key(shop_id,session_id) references public.restaurant_table_sessions(shop_id,id),
  foreign key(shop_id,line_id) references public.restaurant_session_lines(shop_id,id)
);
create index kitchen_events_shop on public.restaurant_kitchen_events(shop_id,id);
alter table public.restaurant_kitchen_events enable row level security;
revoke all on public.restaurant_kitchen_events from public,anon,authenticated;

-- Owner + kitchen only: last acknowledged event cursor, scoped to a specific
-- authenticated staff account. A new device retrieves the exact same backlog.
create table public.restaurant_kitchen_receipts (
  shop_id uuid not null references public.shops(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  last_seen_id bigint not null default 0 check(last_seen_id>=0),
  updated_at timestamptz not null default now(),
  primary key(shop_id,user_id)
);
alter table public.restaurant_kitchen_receipts enable row level security;
revoke all on public.restaurant_kitchen_receipts from public,anon,authenticated;

create function public.restaurant_kitchen_publish_event()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if new.status='ordered'
    and (tg_op='INSERT' or (tg_op='UPDATE' and old.status is distinct from 'ordered')) then
   insert into public.restaurant_kitchen_events(shop_id,session_id,line_id)
     values(new.shop_id,new.session_id,new.id)
   on conflict(shop_id,line_id) do nothing;
 end if;
 return new;
end; $$;
revoke all on function public.restaurant_kitchen_publish_event() from public,anon,authenticated;
create trigger restaurant_kitchen_signal
 after insert or update of status on public.restaurant_session_lines
 for each row execute function public.restaurant_kitchen_publish_event();

-- Backfill existing unserved lines when this staged migration is applied, so a
-- restaurant with open orders doesn't silently lose them in the kitchen inbox.
insert into public.restaurant_kitchen_events(shop_id,session_id,line_id)
select l.shop_id,l.session_id,l.id
from public.restaurant_session_lines l
join public.restaurant_table_sessions ss
 on ss.shop_id=l.shop_id and ss.id=l.session_id
where l.status='ordered' and ss.status='submitted'
on conflict(shop_id,line_id) do nothing;

-- The kitchen inbox is an authenticated read-only projection (never a shared
-- subscription or Supabase Realtime table). Limit the payload and signal
-- overflow explicitly; no figures or guests are sent to the kitchen.
create function public.restaurant_kitchen_inbox(p_shop uuid)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid();v_seen bigint;v_more boolean;v_data jsonb;
begin
 if v_uid is null or not exists(
   select 1 from public.shops s where s.id=p_shop and s.business_kind='restaurant'
   and (s.owner_id=v_uid or exists(
     select 1 from public.restaurant_staff_members m
     where m.shop_id=p_shop and m.user_id=v_uid
      and m.active and m.staff_role='kitchen'
   ))
 ) then raise exception 'Access denied' using errcode='42501';end if;
 select coalesce((select k.last_seen_id from public.restaurant_kitchen_receipts k
   where k.shop_id=p_shop and k.user_id=v_uid),0) into v_seen;
 -- We emit only still ordered lines. Cancelled/served lines do not create
 -- misleading alerts, while preserving the immutable event history.
 select exists(
   select 1 from public.restaurant_kitchen_events e
   join public.restaurant_session_lines l
     on l.shop_id=e.shop_id and l.id=e.line_id
   join public.restaurant_table_sessions ss
     on ss.shop_id=e.shop_id and ss.id=e.session_id
   where e.shop_id=p_shop and e.id>v_seen and l.status='ordered'
     and ss.status='submitted'
   offset 50
 ) into v_more;
 select coalesce(jsonb_agg(jsonb_build_object(
  'id',q.id::text,
  'table',q.table_label,
  'orderReference',q.order_reference,
  'item',q.item_name,
  'quantity',q.quantity,
  'at',q.created_at
 ) order by q.id),'[]'::jsonb) into v_data
 from (
   select e.id,e.created_at,t.label as table_label,ss.order_reference,
     m.name as item_name,l.quantity
   from public.restaurant_kitchen_events e
   join public.restaurant_session_lines l on l.shop_id=e.shop_id and l.id=e.line_id
   join public.restaurant_table_sessions ss
     on ss.shop_id=e.shop_id and ss.id=e.session_id
   join public.restaurant_tables t on t.shop_id=ss.shop_id and t.id=ss.table_id
   join public.restaurant_menu_items m on m.shop_id=l.shop_id and m.id=l.menu_item_id
   where e.shop_id=p_shop and e.id>v_seen and l.status='ordered'
     and ss.status='submitted'
   order by e.id
   limit 50
 ) q;
 return jsonb_build_object('events',v_data,'more',v_more,
   'lastSeenId',v_seen::text);
end; $$;
revoke all on function public.restaurant_kitchen_inbox(uuid) from public,anon;
grant execute on function public.restaurant_kitchen_inbox(uuid) to authenticated;

-- Ack explicit events already shown to this authenticated kitchen user. An
-- acknowledgement does not serve/cancel a dish. No future-id acknowledgements.
create function public.restaurant_kitchen_acknowledge(p_shop uuid,p_through text)
returns text language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid();v_last bigint;v_result bigint;v_cursor bigint;
begin
 if v_uid is null or not exists(
   select 1 from public.shops s where s.id=p_shop and s.business_kind='restaurant'
   and (s.owner_id=v_uid or exists(
      select 1 from public.restaurant_staff_members m
      where m.shop_id=p_shop and m.user_id=v_uid
       and m.active and m.staff_role='kitchen'
   ))
 ) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_through is null or p_through !~ '^[1-9][0-9]{0,18}
 select max(id) into v_last from public.restaurant_kitchen_events where shop_id=p_shop;
 if v_last is null or v_cursor>v_last or not exists(
   select 1 from public.restaurant_kitchen_events
   where shop_id=p_shop and id=v_cursor
 ) then raise exception 'Event cursor does not belong to this restaurant';end if;
 insert into public.restaurant_kitchen_receipts(shop_id,user_id,last_seen_id)
 values(p_shop,v_uid,v_cursor)
 on conflict(shop_id,user_id) do update
 set last_seen_id=greatest(public.restaurant_kitchen_receipts.last_seen_id,excluded.last_seen_id),
 updated_at=now()
 returning last_seen_id into v_result;
 return v_result::text;
end; $$;
revoke all on function public.restaurant_kitchen_acknowledge(uuid,text) from public,anon;
grant execute on function public.restaurant_kitchen_acknowledge(uuid,bigint) to authenticated;
 then
  raise exception 'Invalid event cursor';end if;
 v_cursor:=p_through::bigint;
 select max(id) into v_last from public.restaurant_kitchen_events where shop_id=p_shop;
 if v_last is null or p_through>v_last or not exists(
   select 1 from public.restaurant_kitchen_events
   where shop_id=p_shop and id=p_through
 ) then raise exception 'Event cursor does not belong to this restaurant';end if;
 insert into public.restaurant_kitchen_receipts(shop_id,user_id,last_seen_id)
 values(p_shop,v_uid,p_through)
 on conflict(shop_id,user_id) do update
 set last_seen_id=greatest(public.restaurant_kitchen_receipts.last_seen_id,excluded.last_seen_id),
 updated_at=now()
 returning last_seen_id into v_result;
 return v_result::text;
end; $$;
revoke all on function public.restaurant_kitchen_acknowledge(uuid,bigint) from public,anon;
grant execute on function public.restaurant_kitchen_acknowledge(uuid,bigint) to authenticated;
