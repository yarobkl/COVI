-- One authoritative submission engine for staff and guest. All entry points guard
-- identity, restaurant and session BEFORE calling this private core. The core locks the
-- session and menu rows and assigns exactly one reference.
create function public.restaurant_commit_group(p_shop uuid,p_session uuid,p_leader uuid)
returns text language plpgsql security definer set search_path=''
as $$
declare v_status text; v_count bigint; v_number bigint; v_reference text; v_stock record;
begin
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
revoke all on function public.restaurant_commit_group(uuid,uuid,uuid)
  from public,anon,authenticated,service_role;

-- Owner continues using their unchanged public method / client API.
create or replace function public.restaurant_submit_group(p_shop uuid,p_session uuid,p_leader uuid)
returns text language plpgsql security definer set search_path=''
as $$
begin
 if auth.uid() is null or not exists (
  select 1 from public.shops where id=p_shop and owner_id=auth.uid()
  and business_kind='restaurant'
 ) then raise exception 'Access denied' using errcode='42501'; end if;
 return public.restaurant_commit_group(p_shop,p_session,p_leader);
end; $$;
revoke all on function public.restaurant_submit_group(uuid,uuid,uuid)
 from public,anon;
grant execute on function public.restaurant_submit_group(uuid,uuid,uuid) to authenticated;

-- Guest leader authenticates with their own opaque token, not a participant ID.
-- Replayed submission after lost network response returns the same order reference.
create function public.restaurant_guest_submit(p_qr text,p_secret text)
returns text language plpgsql security definer set search_path=''
as $$
declare v_shop uuid;v_session uuid;v_person uuid;v_status text;v_reference text;
begin
 if p_qr is null or p_qr !~ '^[a-f0-9]{64}$' or
    p_secret is null or p_secret !~ '^[a-f0-9]{64}$' then
   raise exception 'Invalid guest credentials'; end if;
 select ss.shop_id,ss.id,p.id,ss.status,ss.order_reference
 into v_shop,v_session,v_person,v_status,v_reference
 from public.restaurant_participants p
 join public.restaurant_table_sessions ss on ss.shop_id=p.shop_id and ss.id=p.session_id
 join public.restaurant_tables tt on tt.shop_id=ss.shop_id and tt.id=ss.table_id
 where tt.qr_token=p_qr and tt.active and ss.status in ('collecting','submitted')
  and p.participant_token=encode(sha256(convert_to(p_secret,'UTF8')),'hex')
  and p.is_leader and p.ready
 for update of ss;
 if not found then raise exception 'Only the group leader may submit'; end if;
 if v_status='submitted' then return v_reference; end if;
 perform public.restaurant_guest_limit(v_shop,v_person);
 return public.restaurant_commit_group(v_shop,v_session,v_person);
end; $$;
revoke all on function public.restaurant_guest_submit(text,text)
 from public,anon,authenticated;
grant execute on function public.restaurant_guest_submit(text,text) to service_role;
