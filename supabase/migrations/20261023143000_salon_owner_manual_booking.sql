-- Salon: authenticated owner may manually enter an appointment received in person or by phone.
-- Direct INSERT on salon_booking_requests remains revoked: this RPC explicitly enforces ownership.
create function public.salon_add_manual_booking(
  p_shop uuid, p_first_name text, p_last_name text,
  p_phone text, p_requested_at timestamptz, p_service_id uuid default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if (select auth.uid()) is null or not exists (
    select 1 from public.shops s
    where s.id=p_shop and s.owner_id=(select auth.uid()) and s.business_kind='salon'
  ) then raise exception 'Access denied' using errcode='42501'; end if;
  if char_length(btrim(coalesce(p_first_name,''))) not between 1 and 80
     or char_length(btrim(coalesce(p_last_name,''))) not between 1 and 80
     or p_phone is null or p_phone !~ '^[+]?[0-9][0-9 ()-]{5,23} then
    raise exception 'Invalid contact information' using errcode='22023';
  end if;
  if p_requested_at is null or p_requested_at <= now()
     or p_requested_at > now()+interval '180 days' then
    raise exception 'Requested date must be within the next 180 days' using errcode='22023';
  end if;
  if p_service_id is not null and not exists (
    select 1 from public.salon_services sv
    where sv.id=p_service_id and sv.shop_id=p_shop and sv.active
  ) then raise exception 'Service unavailable' using errcode='22023'; end if;
  insert into public.salon_booking_requests(
    shop_id, service_id, first_name, last_name, phone, requested_at, status
  ) values (
    p_shop, p_service_id, btrim(p_first_name), btrim(p_last_name),
    regexp_replace(p_phone,'[^0-9+]','','g'), p_requested_at, 'pending'
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.salon_add_manual_booking(uuid,text,text,text,timestamptz,uuid)
 from public,anon,authenticated;
grant execute on function public.salon_add_manual_booking(uuid,text,text,text,timestamptz,uuid)
 to authenticated;
comment on function public.salon_add_manual_booking(uuid,text,text,text,timestamptz,uuid)
 is 'Authenticated salon owner only: creates a pending request; confirmation and clash protection remain server controlled.';
 then
    raise exception 'Invalid contact information' using errcode='22023';
  end if;
  if p_requested_at is null or p_requested_at <= now()
     or p_requested_at > now()+interval '180 days' then
    raise exception 'Requested date must be within the next 180 days' using errcode='22023';
  end if;
  if p_service_id is not null and not exists (
    select 1 from public.salon_services sv
    where sv.id=p_service_id and sv.shop_id=p_shop and sv.active
  ) then raise exception 'Service unavailable' using errcode='22023'; end if;
  insert into public.salon_booking_requests(
    shop_id, service_id, first_name, last_name, phone, requested_at, status
  ) values (
    p_shop, p_service_id, btrim(p_first_name), btrim(p_last_name),
    regexp_replace(p_phone,'[^0-9+]','','g'), p_requested_at, 'pending'
  ) returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.salon_add_manual_booking(uuid,text,text,text,timestamptz,uuid)
 from public,anon,authenticated;
grant execute on function public.salon_add_manual_booking(uuid,text,text,text,timestamptz,uuid)
 to authenticated;
comment on function public.salon_add_manual_booking(uuid,text,text,text,timestamptz,uuid)
 is 'Authenticated salon owner only: creates a pending request; confirmation and clash protection remain server controlled.';
