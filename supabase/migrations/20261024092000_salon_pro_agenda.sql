-- COVI Salon professionnel — agenda des rendez-vous (lot 3).
-- Un rendez-vous = un client, un collaborateur, une plage horaire et une ou plusieurs
-- prestations. Les doubles réservations d'un même collaborateur sont impossibles, même avec
-- deux appareils en même temps : contrainte d'exclusion (btree_gist) + contrôle dans la fonction.

create extension if not exists btree_gist with schema extensions;

create table public.salon_appointments (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id) on delete cascade,
  client_id uuid,
  client_name text not null check (char_length(btrim(client_name)) between 1 and 160),
  client_phone text check (client_phone is null or client_phone ~ '^[+]?[0-9]{6,20}$'),
  employee_id uuid not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'confirmed' check (status in (
    'pending', 'confirmed', 'arrived', 'in_progress', 'completed', 'cancelled', 'no_show')),
  source text not null default 'manual' check (source in ('manual', 'walk_in', 'request')),
  booking_request_id uuid,
  estimated_price_xaf bigint not null default 0 check (estimated_price_xaf between 0 and 1000000000),
  notes text check (notes is null or char_length(notes) <= 500),
  cancel_reason text check (cancel_reason is null or char_length(cancel_reason) <= 200),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (shop_id, id),
  foreign key (shop_id, client_id) references public.salon_clients (shop_id, id),
  foreign key (shop_id, employee_id) references public.employees (shop_id, id),
  foreign key (shop_id, booking_request_id) references public.salon_booking_requests (shop_id, id),
  check (ends_at > starts_at and ends_at <= starts_at + interval '12 hours'),
  -- Défense en profondeur : deux rendez-vous actifs d'un même collaborateur ne se chevauchent jamais.
  constraint salon_no_double_booking exclude using gist (
    employee_id with =,
    tstzrange(starts_at, ends_at, '[)') with &&
  ) where (status in ('pending', 'confirmed', 'arrived', 'in_progress', 'completed'))
);
create index salon_appointments_by_day on public.salon_appointments (shop_id, starts_at);
create index salon_appointments_by_client on public.salon_appointments (shop_id, client_id, starts_at desc);
create unique index salon_appointments_one_per_request on public.salon_appointments (booking_request_id)
  where booking_request_id is not null and status not in ('cancelled', 'no_show');

create table public.salon_appointment_services (
  shop_id uuid not null references public.shops(id) on delete cascade,
  appointment_id uuid not null,
  position smallint not null check (position between 1 and 20),
  service_id uuid not null,
  name text not null,
  price_xaf bigint not null check (price_xaf between 0 and 1000000000),
  duration_minutes integer not null check (duration_minutes between 5 and 720),
  primary key (appointment_id, position),
  foreign key (shop_id, appointment_id) references public.salon_appointments (shop_id, id) on delete cascade,
  foreign key (shop_id, service_id) references public.salon_services (shop_id, id)
);

alter table public.salon_appointments enable row level security;
alter table public.salon_appointment_services enable row level security;
revoke all on public.salon_appointments, public.salon_appointment_services
  from public, anon, authenticated;
create trigger immutable_shop_salon_appointment before update on public.salon_appointments
  for each row execute function public.prevent_sector_shop_reassignment();

-- Fuseau du salon (réglages), Brazzaville par défaut.
create function public.salon_tz(p_shop uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select time_zone from public.salon_settings where shop_id = p_shop), 'Africa/Brazzaville')
$$;

-- Vérifie qu'une plage est réservable ; lève une erreur métier lisible sinon.
create function public.salon_check_slot(
  p_shop uuid, p_employee uuid, p_starts timestamptz, p_ends timestamptz,
  p_service_ids uuid[], p_ignore uuid
)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_tz text := public.salon_tz(p_shop);
  v_local_start timestamp := p_starts at time zone v_tz;
  v_local_end timestamp := p_ends at time zone v_tz;
  v_day smallint := extract(isodow from v_local_start)::smallint;
  v_open time;
  v_close time;
begin
  if not exists (
    select 1 from public.employees e join public.salon_staff_profiles p on p.employee_id = e.id
    where e.id = p_employee and e.shop_id = p_shop and e.active
  ) then
    raise exception 'Collaborator unavailable' using errcode = '22023';
  end if;
  if v_local_end::date <> v_local_start::date and v_local_end::time <> time '00:00' then
    raise exception 'Appointment must stay within one day' using errcode = '22023';
  end if;
  if exists (select 1 from public.salon_opening_hours where shop_id = p_shop) then
    select opens_at, closes_at into v_open, v_close
    from public.salon_opening_hours where shop_id = p_shop and weekday = v_day;
    if not found or v_local_start::time < v_open
       or (v_local_end::time > v_close and v_local_end::date = v_local_start::date) then
      raise exception 'Salon closed at this time' using errcode = '22023';
    end if;
  end if;
  if exists (select 1 from public.salon_staff_hours where employee_id = p_employee) then
    select starts_at, ends_at into v_open, v_close
    from public.salon_staff_hours where employee_id = p_employee and weekday = v_day;
    if not found or v_local_start::time < v_open
       or (v_local_end::time > v_close and v_local_end::date = v_local_start::date) then
      raise exception 'Collaborator not working at this time' using errcode = '22023';
    end if;
  end if;
  if exists (select 1 from public.salon_staff_absences
             where employee_id = p_employee and day = v_local_start::date) then
    raise exception 'Collaborator absent this day' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_service_ids, '{}'::uuid[])) x(id)
    where exists (select 1 from public.salon_staff_services ss where ss.service_id = x.id)
      and not exists (select 1 from public.salon_staff_services ss
                      where ss.service_id = x.id and ss.employee_id = p_employee)
  ) then
    raise exception 'Collaborator not qualified for this service' using errcode = '22023';
  end if;
  if exists (
    select 1 from public.salon_appointments a
    where a.shop_id = p_shop and a.employee_id = p_employee and a.id is distinct from p_ignore
      and a.status in ('pending', 'confirmed', 'arrived', 'in_progress', 'completed')
      and tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(p_starts, p_ends, '[)')
  ) then
    raise exception 'Collaborator already booked at this time' using errcode = '23P01';
  end if;
end;
$$;

-- Crée ou modifie (reporte) un rendez-vous. p_duration_minutes null = somme des prestations.
create function public.salon_appointment_save(
  p_shop uuid, p_id uuid, p_client_id uuid, p_client_name text, p_client_phone text,
  p_employee uuid, p_starts_at timestamptz, p_service_ids uuid[], p_duration_minutes integer,
  p_notes text, p_status text default 'confirmed', p_source text default 'manual',
  p_request_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'agenda_write');
  v_id uuid := p_id;
  v_old public.salon_appointments%rowtype;
  v_duration integer;
  v_price bigint;
  v_name text := nullif(btrim(p_client_name), '');
  v_phone text := nullif(regexp_replace(coalesce(p_client_phone, ''), '[^0-9+]', '', 'g'), '');
  v_status text := coalesce(p_status, 'confirmed');
  v_source text := coalesce(p_source, 'manual');
  v_ends timestamptz;
begin
  if p_service_ids is null or cardinality(p_service_ids) not between 1 and 20 then
    raise exception 'Choose at least one service' using errcode = '22023';
  end if;
  if (select count(*) from public.salon_services sv
      where sv.shop_id = p_shop and sv.active and sv.id = any(p_service_ids))
     <> (select count(distinct x) from unnest(p_service_ids) x) then
    raise exception 'Service unavailable' using errcode = '22023';
  end if;
  if p_client_id is not null then
    select coalesce(v_name, btrim(c.first_name || ' ' || coalesce(c.last_name, ''))),
           coalesce(v_phone, c.phone)
    into v_name, v_phone
    from public.salon_clients c
    where c.id = p_client_id and c.shop_id = p_shop and c.anonymized_at is null;
    if not found then raise exception 'Client not found' using errcode = '22023'; end if;
  end if;
  if v_name is null then raise exception 'Client name is required' using errcode = '22023'; end if;
  if p_starts_at is null or p_starts_at > now() + interval '366 days' then
    raise exception 'Invalid date' using errcode = '22023';
  end if;

  select coalesce(sum(sv.duration_minutes), 0), coalesce(sum(sv.price_xaf), 0)
  into v_duration, v_price
  from unnest(p_service_ids) with ordinality x(id, n)
  join public.salon_services sv on sv.id = x.id and sv.shop_id = p_shop;
  v_duration := coalesce(p_duration_minutes, v_duration);
  if v_duration not between 5 and 720 then
    raise exception 'Invalid duration' using errcode = '22023';
  end if;
  v_ends := p_starts_at + v_duration * interval '1 minute';

  -- Sérialise les écritures de l'agenda d'un salon (deux appareils, même créneau).
  perform 1 from public.shops where id = p_shop for update;

  if v_id is null then
    if v_source = 'walk_in' then
      v_status := 'arrived';
      if p_starts_at < now() - interval '15 minutes' or p_starts_at > now() + interval '15 minutes' then
        raise exception 'A walk-in starts now' using errcode = '22023';
      end if;
    else
      if v_status not in ('pending', 'confirmed') then
        raise exception 'Invalid status' using errcode = '22023';
      end if;
      if p_starts_at <= now() - interval '5 minutes' then
        raise exception 'Appointments cannot be created in the past' using errcode = '22023';
      end if;
    end if;
    perform public.salon_check_slot(p_shop, p_employee, p_starts_at, v_ends, p_service_ids, null);
    insert into public.salon_appointments (shop_id, client_id, client_name, client_phone,
      employee_id, starts_at, ends_at, status, source, booking_request_id,
      estimated_price_xaf, notes, created_by)
    values (p_shop, p_client_id, v_name, v_phone, p_employee, p_starts_at, v_ends, v_status,
      v_source, p_request_id, v_price, nullif(btrim(p_notes), ''), auth.uid())
    returning id into v_id;
  else
    select * into v_old from public.salon_appointments
    where id = v_id and shop_id = p_shop for update;
    if not found then raise exception 'Appointment not found' using errcode = '42501'; end if;
    if v_old.status not in ('pending', 'confirmed', 'arrived') then
      raise exception 'This appointment can no longer be changed' using errcode = '22023';
    end if;
    if p_starts_at <> v_old.starts_at and p_starts_at <= now() - interval '5 minutes' then
      raise exception 'Appointments cannot be moved to the past' using errcode = '22023';
    end if;
    if exists (select 1 from public.salon_tickets t
               where t.appointment_id = v_id and t.status <> 'cancelled') then
      raise exception 'A checkout is already open for this appointment' using errcode = '22023';
    end if;
    perform public.salon_check_slot(p_shop, p_employee, p_starts_at, v_ends, p_service_ids, v_id);
    update public.salon_appointments set client_id = p_client_id, client_name = v_name,
      client_phone = v_phone, employee_id = p_employee, starts_at = p_starts_at, ends_at = v_ends,
      estimated_price_xaf = v_price, notes = nullif(btrim(p_notes), ''), updated_at = now()
    where id = v_id;
    delete from public.salon_appointment_services where appointment_id = v_id;
  end if;

  insert into public.salon_appointment_services (shop_id, appointment_id, position, service_id,
                                                 name, price_xaf, duration_minutes)
  select p_shop, v_id, x.n, sv.id, sv.name, sv.price_xaf, sv.duration_minutes
  from unnest(p_service_ids) with ordinality x(id, n)
  join public.salon_services sv on sv.id = x.id and sv.shop_id = p_shop;

  perform public.salon_log(p_shop, v_role,
    case when p_id is null then 'appointment_created' else 'appointment_rescheduled' end, v_id,
    jsonb_build_object('starts_at', p_starts_at, 'employee_id', p_employee,
                       'previous_starts_at', v_old.starts_at));
  return v_id;
exception
  when exclusion_violation then
    raise exception 'Collaborator already booked at this time' using errcode = '23P01';
end;
$$;

-- Changement de statut. Le coiffeur ne gère que ses rendez-vous et ne peut pas annuler.
create function public.salon_appointment_set_status(
  p_shop uuid, p_id uuid, p_status text, p_reason text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'agenda_own');
  v_a public.salon_appointments%rowtype;
  v_ok boolean;
begin
  select * into v_a from public.salon_appointments where id = p_id and shop_id = p_shop for update;
  if not found then raise exception 'Appointment not found' using errcode = '42501'; end if;
  if v_role = 'stylist' then
    if v_a.employee_id is distinct from public.salon_my_employee(p_shop) then
      raise exception 'Access denied' using errcode = '42501';
    end if;
    if p_status not in ('arrived', 'in_progress', 'completed') then
      raise exception 'Access denied' using errcode = '42501';
    end if;
  end if;
  if v_a.status = p_status then return p_status; end if;
  v_ok := case v_a.status
    when 'pending' then p_status in ('confirmed', 'cancelled')
    when 'confirmed' then p_status in ('arrived', 'in_progress', 'cancelled', 'no_show')
    when 'arrived' then p_status in ('in_progress', 'cancelled', 'no_show')
    when 'in_progress' then p_status in ('completed')
    else false
  end;
  if not v_ok then raise exception 'Invalid status transition' using errcode = '22023'; end if;
  if p_status = 'no_show' and v_a.starts_at > now() then
    raise exception 'A client cannot be absent before the appointment' using errcode = '22023';
  end if;
  if p_status in ('cancelled', 'no_show') and exists (
      select 1 from public.salon_tickets t where t.appointment_id = p_id and t.status <> 'cancelled') then
    raise exception 'Cancel the open checkout first' using errcode = '22023';
  end if;
  update public.salon_appointments set status = p_status, updated_at = now(),
    cancel_reason = case when p_status in ('cancelled', 'no_show') then nullif(btrim(p_reason), '')
                         else cancel_reason end
  where id = p_id;
  if v_a.booking_request_id is not null and p_status in ('cancelled', 'no_show', 'completed') then
    update public.salon_booking_requests set status = p_status
    where id = v_a.booking_request_id and status = 'confirmed';
  end if;
  perform public.salon_log(p_shop, v_role, 'appointment_status', p_id,
    jsonb_build_object('from', v_a.status, 'to', p_status));
  return p_status;
end;
$$;

-- Transforme une demande en attente (ancien agenda) en rendez-vous avec un collaborateur.
create function public.salon_request_to_appointment(p_shop uuid, p_request uuid, p_employee uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'agenda_write');
  v_r public.salon_booking_requests%rowtype;
  v_id uuid;
begin
  select * into v_r from public.salon_booking_requests
  where id = p_request and shop_id = p_shop for update;
  if not found then raise exception 'Request not found' using errcode = '42501'; end if;
  if v_r.status <> 'pending' or v_r.service_id is null then
    raise exception 'This request cannot be scheduled' using errcode = '22023';
  end if;
  v_id := public.salon_appointment_save(p_shop, null, null,
    btrim(v_r.first_name || ' ' || v_r.last_name), v_r.phone, p_employee, v_r.requested_at,
    array[v_r.service_id], v_r.duration_minutes, null, 'confirmed', 'request', v_r.id);
  update public.salon_booking_requests set status = 'confirmed' where id = p_request;
  return v_id;
end;
$$;

-- Agenda d'une période (vue jour / semaine / liste). Le coiffeur ne voit que ses rendez-vous.
create function public.salon_agenda(p_shop uuid, p_from timestamptz, p_to timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'agenda_own');
  v_me uuid := case when v_role = 'stylist' then public.salon_my_employee(p_shop) end;
begin
  if p_from is null or p_to is null or p_to <= p_from or p_to > p_from + interval '42 days' then
    raise exception 'Invalid period' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'role', v_role,
    'time_zone', public.salon_tz(p_shop),
    'appointments', coalesce((select jsonb_agg(jsonb_build_object(
        'id', a.id, 'client_id', a.client_id, 'client_name', a.client_name,
        'client_phone', a.client_phone, 'employee_id', a.employee_id,
        'employee_name', e.full_name, 'starts_at', a.starts_at, 'ends_at', a.ends_at,
        'status', a.status, 'source', a.source, 'estimated_price_xaf', a.estimated_price_xaf,
        'notes', a.notes,
        'services', coalesce((select jsonb_agg(jsonb_build_object('service_id', s.service_id,
            'name', s.name, 'price_xaf', s.price_xaf, 'duration_minutes', s.duration_minutes)
            order by s.position)
          from public.salon_appointment_services s where s.appointment_id = a.id), '[]'::jsonb),
        'ticket', (select jsonb_build_object('id', t.id, 'status', t.status)
                   from public.salon_tickets t
                   where t.appointment_id = a.id and t.status <> 'cancelled' limit 1))
        order by a.starts_at)
      from public.salon_appointments a
      join public.employees e on e.id = a.employee_id
      where a.shop_id = p_shop and a.starts_at < p_to and a.ends_at > p_from
        and (v_me is null or a.employee_id = v_me)
        and (v_role <> 'stylist' or v_me is not null)), '[]'::jsonb),
    'pending_requests', case when v_role = 'stylist' then '[]'::jsonb else
      coalesce((select jsonb_agg(jsonb_build_object('id', r.id,
          'client_name', btrim(r.first_name || ' ' || r.last_name), 'phone', r.phone,
          'requested_at', r.requested_at, 'service_id', r.service_id,
          'duration_minutes', r.duration_minutes) order by r.requested_at)
        from public.salon_booking_requests r
        where r.shop_id = p_shop and r.status = 'pending' and r.requested_at > now()), '[]'::jsonb)
      end
  );
end;
$$;

-- Fiche client avec historique.
create function public.salon_client_get(p_shop uuid, p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'clients');
  v jsonb;
begin
  select jsonb_build_object(
    'id', c.id, 'first_name', c.first_name, 'last_name', c.last_name, 'phone', c.phone,
    'email', c.email, 'preferences', c.preferences, 'preferences_consent', c.preferences_consent,
    'reminder_consent', c.reminder_consent, 'consent_recorded_at', c.consent_recorded_at,
    'anonymized', c.anonymized_at is not null, 'created_at', c.created_at,
    'visits', (select count(*) from public.salon_appointments a
               where a.client_id = c.id and a.status = 'completed'),
    'no_shows', (select count(*) from public.salon_appointments a
                 where a.client_id = c.id and a.status = 'no_show'),
    'total_spent_xaf', coalesce((select sum(t.paid_xaf - t.refunded_xaf) from public.salon_tickets t
                                 where t.client_id = c.id and t.status in ('paid', 'partially_refunded', 'refunded')), 0),
    'last_visit_at', (select max(a.starts_at) from public.salon_appointments a
                      where a.client_id = c.id and a.status = 'completed'),
    'upcoming', coalesce((select jsonb_agg(jsonb_build_object('id', a.id, 'starts_at', a.starts_at,
        'status', a.status, 'employee_name', e.full_name) order by a.starts_at)
      from public.salon_appointments a join public.employees e on e.id = a.employee_id
      where a.client_id = c.id and a.starts_at >= now() and a.status in ('pending', 'confirmed')), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(h order by h ->> 'starts_at' desc) from (
        select jsonb_build_object('id', a.id, 'starts_at', a.starts_at, 'status', a.status,
          'employee_name', e.full_name,
          'services', (select string_agg(s.name, ', ' order by s.position)
                       from public.salon_appointment_services s where s.appointment_id = a.id)) h
        from public.salon_appointments a join public.employees e on e.id = a.employee_id
        where a.client_id = c.id and a.starts_at < now()
        order by a.starts_at desc limit 50) x), '[]'::jsonb)
  ) into v
  from public.salon_clients c where c.id = p_id and c.shop_id = p_shop;
  if v is null then raise exception 'Client not found' using errcode = '42501'; end if;
  return v;
end;
$$;

revoke all on function public.salon_tz(uuid),
  public.salon_check_slot(uuid, uuid, timestamptz, timestamptz, uuid[], uuid)
  from public, anon, authenticated;
revoke all on function
  public.salon_appointment_save(uuid, uuid, uuid, text, text, uuid, timestamptz, uuid[], integer, text, text, text, uuid),
  public.salon_appointment_set_status(uuid, uuid, text, text),
  public.salon_request_to_appointment(uuid, uuid, uuid),
  public.salon_agenda(uuid, timestamptz, timestamptz),
  public.salon_client_get(uuid, uuid),
  public.salon_clients_search(uuid, text, integer),
  public.salon_client_save(uuid, uuid, text, text, text, text, text, boolean, boolean, boolean)
  from public, anon;
grant execute on function
  public.salon_appointment_save(uuid, uuid, uuid, text, text, uuid, timestamptz, uuid[], integer, text, text, text, uuid),
  public.salon_appointment_set_status(uuid, uuid, text, text),
  public.salon_request_to_appointment(uuid, uuid, uuid),
  public.salon_agenda(uuid, timestamptz, timestamptz),
  public.salon_client_get(uuid, uuid),
  public.salon_clients_search(uuid, text, integer),
  public.salon_client_save(uuid, uuid, text, text, text, text, text, boolean, boolean, boolean)
  to authenticated;
