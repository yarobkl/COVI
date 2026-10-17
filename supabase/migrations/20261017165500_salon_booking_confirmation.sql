-- Salon: private, deterministic appointment confirmation.
-- Public booking remains disabled until security gateway/anti-spam.
-- V1: one simultaneous confirmed service per salon; staffing capacity follows later.
alter table public.salon_booking_requests
  add column duration_minutes integer check(duration_minutes between 5 and 720);

-- Preserve duration at the time of acceptance; later edits to salon_services
-- cannot retroactively change the length of confirmed appointments.
create function public.salon_booking_fill_duration()
returns trigger language plpgsql security invoker set search_path=''
as $$
begin
 if new.duration_minutes is null then
   select sv.duration_minutes into new.duration_minutes
     from public.salon_services sv
     where sv.id=new.service_id and sv.shop_id=new.shop_id;
 end if;
 if new.duration_minutes is null then new.duration_minutes:=30; end if;
 return new;
end; $$;
revoke all on function public.salon_booking_fill_duration() from public,anon,authenticated;
create trigger salon_duration_on_insert before insert on public.salon_booking_requests
for each row execute function public.salon_booking_fill_duration();

-- For a future public request, freeze the advertised service duration at insertion.
-- No caller is permitted to edit the requested start time or status directly.
revoke update on public.salon_booking_requests from authenticated;
revoke insert on public.salon_booking_requests from authenticated;

create function public.salon_change_booking_status(
 p_shop uuid,p_booking uuid,p_status text
) returns text language plpgsql security definer set search_path=''
as $$
declare v_booking public.salon_booking_requests%rowtype;
begin
 if auth.uid() is null or not exists (
  select 1 from public.shops s
  where s.id=p_shop and s.owner_id=auth.uid() and s.business_kind='salon'
 ) then raise exception 'Access denied' using errcode='42501'; end if;
 if p_status not in ('confirmed','declined','cancelled','completed','no_show') then
  raise exception 'Unsupported status'; end if;
 -- The salon lock serializes two owner devices confirming overlapping requests.
 perform 1 from public.shops where id=p_shop for update;
 select * into v_booking from public.salon_booking_requests
 where shop_id=p_shop and id=p_booking for update;
 if not found then raise exception 'Booking not found'; end if;
 if v_booking.status=p_status then return p_status; end if;
 if v_booking.status='pending' and p_status not in ('confirmed','declined','cancelled') then
  raise exception 'Invalid status transition';
 end if;
 if v_booking.status='confirmed' and p_status not in ('completed','cancelled','no_show') then
  raise exception 'Invalid status transition';
 end if;
 if v_booking.status not in ('pending','confirmed') then
  raise exception 'This request cannot change status';
 end if;
 if p_status='confirmed' then
   if v_booking.requested_at<=now() then raise exception 'Past appointments cannot be confirmed'; end if;
   if exists(
    select 1 from public.salon_booking_requests other
    where other.shop_id=p_shop and other.status='confirmed'
      and other.id<>p_booking
      and tstzrange(other.requested_at,
        other.requested_at + other.duration_minutes * interval '1 minute', '[)')
        && tstzrange(v_booking.requested_at,
          v_booking.requested_at + v_booking.duration_minutes * interval '1 minute','[)')
   ) then raise exception 'This salon time slot is already confirmed'; end if;
 end if;
 update public.salon_booking_requests set status=p_status
 where id=p_booking and shop_id=p_shop;
 return p_status;
end; $$;
revoke all on function public.salon_change_booking_status(uuid,uuid,text)
 from public,anon,authenticated;
grant execute on function public.salon_change_booking_status(uuid,uuid,text)
 to authenticated;

comment on function public.salon_change_booking_status(uuid,uuid,text)
 is 'Owner-only workflow; checks collisions among confirmed bookings. Pending requests never guarantee a free slot.';
