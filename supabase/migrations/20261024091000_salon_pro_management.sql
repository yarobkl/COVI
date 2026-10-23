-- COVI Salon professionnel — réglages, catalogue, collaborateurs, clients (lot 2/2).
-- Fonctions SECURITY DEFINER uniquement ; chacune vérifie le rôle avec salon_require.

-- 1. Réglages et horaires ----------------------------------------------------------------------
create function public.salon_settings_get(p_shop uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'read_catalog');
begin
  return jsonb_build_object(
    'role', v_role,
    'shop', (select jsonb_build_object('id', s.id, 'name', s.name, 'city', s.city,
               'country', s.country, 'neighborhood', s.neighborhood,
               'address_line', s.address_line, 'currency', s.currency)
             from public.shops s where s.id = p_shop),
    'settings', coalesce((select jsonb_build_object(
        'salon_type', st.salon_type, 'owner_name', st.owner_name,
        'business_phone', st.business_phone, 'expected_staff_count', st.expected_staff_count,
        'time_zone', st.time_zone)
      from public.salon_settings st where st.shop_id = p_shop),
      jsonb_build_object('salon_type', 'mixed', 'owner_name', null, 'business_phone', null,
                         'expected_staff_count', null, 'time_zone', 'Africa/Brazzaville')),
    'opening_hours', coalesce((select jsonb_agg(jsonb_build_object(
        'weekday', h.weekday, 'opens_at', to_char(h.opens_at, 'HH24:MI'),
        'closes_at', to_char(h.closes_at, 'HH24:MI')) order by h.weekday)
      from public.salon_opening_hours h where h.shop_id = p_shop), '[]'::jsonb),
    'configured', exists (select 1 from public.salon_settings st where st.shop_id = p_shop)
  );
end;
$$;

-- p_hours : [{"weekday":1,"opens_at":"08:00","closes_at":"19:00"}, …] ; [] = pas de contrôle.
create function public.salon_settings_save(
  p_shop uuid, p_salon_type text, p_owner_name text, p_business_phone text,
  p_expected_staff_count integer, p_time_zone text, p_hours jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'settings');
  v_item jsonb;
  v_day smallint;
  v_open time;
  v_close time;
  v_phone text := nullif(regexp_replace(coalesce(p_business_phone, ''), '[^0-9+]', '', 'g'), '');
begin
  if p_hours is null or jsonb_typeof(p_hours) <> 'array' or jsonb_array_length(p_hours) > 7 then
    raise exception 'Invalid opening hours' using errcode = '22023';
  end if;
  insert into public.salon_settings (shop_id, salon_type, owner_name, business_phone,
                                     expected_staff_count, time_zone, updated_at)
  values (p_shop, coalesce(p_salon_type, 'mixed'), nullif(btrim(p_owner_name), ''), v_phone,
          p_expected_staff_count, coalesce(p_time_zone, 'Africa/Brazzaville'), now())
  on conflict (shop_id) do update set
    salon_type = excluded.salon_type, owner_name = excluded.owner_name,
    business_phone = excluded.business_phone,
    expected_staff_count = excluded.expected_staff_count,
    time_zone = excluded.time_zone, updated_at = now();

  delete from public.salon_opening_hours where shop_id = p_shop;
  for v_item in select value from jsonb_array_elements(p_hours) loop
    begin
      v_day := (v_item ->> 'weekday')::smallint;
      v_open := (v_item ->> 'opens_at')::time;
      v_close := (v_item ->> 'closes_at')::time;
    exception when others then
      raise exception 'Invalid opening hours' using errcode = '22023';
    end;
    if v_day is null or v_open is null or v_close is null then
      raise exception 'Invalid opening hours' using errcode = '22023';
    end if;
    insert into public.salon_opening_hours (shop_id, weekday, opens_at, closes_at)
    values (p_shop, v_day, v_open, v_close);
  end loop;
  perform public.salon_log(p_shop, v_role, 'settings_saved', p_shop,
    jsonb_build_object('days', jsonb_array_length(p_hours)));
  return public.salon_settings_get(p_shop);
end;
$$;

-- 2. Catalogue des prestations ------------------------------------------------------------------
create function public.salon_catalog(p_shop uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'read_catalog');
  v_costs boolean := public.salon_allowed(v_role, 'catalog');
begin
  return jsonb_build_object(
    'services', coalesce((select jsonb_agg(jsonb_build_object(
        'id', sv.id, 'name', sv.name, 'category', sv.category, 'description', sv.description,
        'price_xaf', sv.price_xaf, 'duration_minutes', sv.duration_minutes,
        'direct_cost_xaf', case when v_costs then sv.direct_cost_xaf end,
        'active', sv.active,
        'employee_ids', coalesce((select jsonb_agg(ss.employee_id)
          from public.salon_staff_services ss where ss.service_id = sv.id), '[]'::jsonb))
        order by sv.active desc, coalesce(sv.category, ''), sv.name)
      from public.salon_services sv where sv.shop_id = p_shop), '[]'::jsonb),
    'staff', coalesce((select jsonb_agg(jsonb_build_object(
        'employee_id', e.id, 'full_name', e.full_name, 'job_title', e.job_title,
        'active', e.active and p.employee_id is not null, 'agenda_color', p.agenda_color)
        order by e.full_name)
      from public.employees e
      join public.salon_staff_profiles p on p.employee_id = e.id
      where e.shop_id = p_shop), '[]'::jsonb)
  );
end;
$$;

create function public.salon_service_save(
  p_shop uuid, p_id uuid, p_name text, p_category text, p_description text,
  p_price_xaf bigint, p_duration_minutes integer, p_direct_cost_xaf bigint, p_active boolean,
  p_employee_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'catalog');
  v_id uuid := p_id;
begin
  if p_name is null or char_length(btrim(p_name)) not between 2 and 120 then
    raise exception 'Service name is required' using errcode = '22023';
  end if;
  if p_price_xaf is null or p_price_xaf not between 0 and 1000000000
     or p_duration_minutes is null or p_duration_minutes not between 5 and 720
     or coalesce(p_direct_cost_xaf, 0) not between 0 and 1000000000 then
    raise exception 'Invalid price or duration' using errcode = '22023';
  end if;
  if p_employee_ids is not null and exists (
    select 1 from unnest(p_employee_ids) x(id)
    where not exists (select 1 from public.salon_staff_profiles p
                      where p.employee_id = x.id and p.shop_id = p_shop)
  ) then
    raise exception 'Unknown collaborator' using errcode = '22023';
  end if;

  if v_id is null then
    insert into public.salon_services (shop_id, name, category, description, price_xaf,
                                       duration_minutes, direct_cost_xaf, active)
    values (p_shop, btrim(p_name), nullif(btrim(p_category), ''), nullif(btrim(p_description), ''),
            p_price_xaf, p_duration_minutes, coalesce(p_direct_cost_xaf, 0), coalesce(p_active, true))
    returning id into v_id;
  else
    update public.salon_services set
      name = btrim(p_name), category = nullif(btrim(p_category), ''),
      description = nullif(btrim(p_description), ''), price_xaf = p_price_xaf,
      duration_minutes = p_duration_minutes, direct_cost_xaf = coalesce(p_direct_cost_xaf, 0),
      active = coalesce(p_active, true), updated_at = now()
    where id = v_id and shop_id = p_shop;
    if not found then raise exception 'Service not found' using errcode = '42501'; end if;
  end if;

  if p_employee_ids is not null then
    delete from public.salon_staff_services where service_id = v_id and shop_id = p_shop;
    insert into public.salon_staff_services (shop_id, employee_id, service_id)
    select distinct p_shop, x.id, v_id from unnest(p_employee_ids) x(id);
  end if;
  perform public.salon_log(p_shop, v_role, 'service_saved', v_id,
    jsonb_build_object('price_xaf', p_price_xaf, 'active', coalesce(p_active, true)));
  return v_id;
end;
$$;

-- 3. Collaborateurs ------------------------------------------------------------------------------
create function public.salon_staff_list(p_shop uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'staff');
begin
  return coalesce((select jsonb_agg(jsonb_build_object(
      'employee_id', e.id, 'full_name', e.full_name, 'job_title', e.job_title,
      'active', e.active, 'phone', p.phone, 'agenda_color', p.agenda_color,
      'commission_mode', p.commission_mode, 'commission_percent', p.commission_percent,
      'commission_fixed_xaf', p.commission_fixed_xaf,
      'service_ids', coalesce((select jsonb_agg(ss.service_id)
        from public.salon_staff_services ss where ss.employee_id = e.id), '[]'::jsonb),
      'hours', coalesce((select jsonb_agg(jsonb_build_object('weekday', h.weekday,
          'starts_at', to_char(h.starts_at, 'HH24:MI'), 'ends_at', to_char(h.ends_at, 'HH24:MI'))
          order by h.weekday)
        from public.salon_staff_hours h where h.employee_id = e.id), '[]'::jsonb),
      'absences', coalesce((select jsonb_agg(jsonb_build_object('day', a.day, 'reason', a.reason)
          order by a.day)
        from public.salon_staff_absences a where a.employee_id = e.id and a.day >= current_date - 1),
        '[]'::jsonb),
      'account', (select jsonb_build_object('member_id', m.id, 'role', m.role, 'active', m.active,
                    'display_name', m.display_name)
                  from public.salon_staff_members m
                  where m.employee_id = e.id and m.shop_id = p_shop
                  order by m.active desc, m.created_at desc limit 1))
      order by e.active desc, e.full_name)
    from public.employees e
    join public.salon_staff_profiles p on p.employee_id = e.id
    where e.shop_id = p_shop), '[]'::jsonb);
end;
$$;

create function public.salon_staff_save(
  p_shop uuid, p_employee uuid, p_full_name text, p_job_title text, p_phone text,
  p_commission_mode text, p_commission_percent numeric, p_commission_fixed_xaf bigint,
  p_agenda_color text, p_active boolean, p_service_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'staff');
  v_id uuid := p_employee;
  v_mode text := coalesce(p_commission_mode, 'none');
  v_pct numeric := case when coalesce(p_commission_mode, 'none') = 'percent' then coalesce(p_commission_percent, 0) else 0 end;
  v_fixed bigint := case when coalesce(p_commission_mode, 'none') = 'fixed' then coalesce(p_commission_fixed_xaf, 0) else 0 end;
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
begin
  -- Les règles de commission sont des données de paie : réservées au propriétaire.
  if v_role <> 'owner' then
    if (v_id is null and v_mode <> 'none') or (v_id is not null and exists (
        select 1 from public.salon_staff_profiles p where p.employee_id = v_id and p.shop_id = p_shop
          and (p.commission_mode, p.commission_percent, p.commission_fixed_xaf)
              is distinct from (v_mode, v_pct, v_fixed::bigint))) then
      raise exception 'Only the owner can set commissions' using errcode = '42501';
    end if;
  end if;
  if v_id is null then
    insert into public.employees (shop_id, full_name, job_title, compensation_mode,
                                  monthly_salary, commission_percent, active)
    values (p_shop, btrim(coalesce(p_full_name, '')), btrim(coalesce(p_job_title, '')),
            'fixed', 0, 0, coalesce(p_active, true))
    returning id into v_id;
    insert into public.salon_staff_profiles (employee_id, shop_id, phone, commission_mode,
      commission_percent, commission_fixed_xaf, agenda_color)
    values (v_id, p_shop, v_phone, v_mode, v_pct, v_fixed, coalesce(p_agenda_color, '#17408b'));
  else
    update public.employees set full_name = btrim(coalesce(p_full_name, '')),
      job_title = btrim(coalesce(p_job_title, '')), active = coalesce(p_active, true),
      updated_at = now()
    where id = v_id and shop_id = p_shop;
    if not found then raise exception 'Collaborator not found' using errcode = '42501'; end if;
    insert into public.salon_staff_profiles (employee_id, shop_id, phone, commission_mode,
      commission_percent, commission_fixed_xaf, agenda_color)
    values (v_id, p_shop, v_phone, v_mode, v_pct, v_fixed, coalesce(p_agenda_color, '#17408b'))
    on conflict (employee_id) do update set phone = excluded.phone,
      commission_mode = excluded.commission_mode, commission_percent = excluded.commission_percent,
      commission_fixed_xaf = excluded.commission_fixed_xaf, agenda_color = excluded.agenda_color,
      updated_at = now();
  end if;
  if p_service_ids is not null then
    if exists (select 1 from unnest(p_service_ids) x(id) where not exists (
        select 1 from public.salon_services sv where sv.id = x.id and sv.shop_id = p_shop)) then
      raise exception 'Unknown service' using errcode = '22023';
    end if;
    delete from public.salon_staff_services where employee_id = v_id and shop_id = p_shop;
    insert into public.salon_staff_services (shop_id, employee_id, service_id)
    select distinct p_shop, v_id, x.id from unnest(p_service_ids) x(id);
  end if;
  perform public.salon_log(p_shop, v_role, 'staff_saved', v_id,
    jsonb_build_object('commission_mode', v_mode, 'active', coalesce(p_active, true)));
  return v_id;
end;
$$;

-- p_hours : [{"weekday":1,"starts_at":"09:00","ends_at":"18:00"}, …] ; jour absent = repos.
create function public.salon_staff_hours_set(p_shop uuid, p_employee uuid, p_hours jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'staff');
  v_item jsonb;
begin
  if not exists (select 1 from public.salon_staff_profiles p
                 where p.employee_id = p_employee and p.shop_id = p_shop) then
    raise exception 'Collaborator not found' using errcode = '42501';
  end if;
  if p_hours is null or jsonb_typeof(p_hours) <> 'array' or jsonb_array_length(p_hours) > 7 then
    raise exception 'Invalid working hours' using errcode = '22023';
  end if;
  delete from public.salon_staff_hours where employee_id = p_employee and shop_id = p_shop;
  for v_item in select value from jsonb_array_elements(p_hours) loop
    begin
      insert into public.salon_staff_hours (shop_id, employee_id, weekday, starts_at, ends_at)
      values (p_shop, p_employee, (v_item ->> 'weekday')::smallint,
              (v_item ->> 'starts_at')::time, (v_item ->> 'ends_at')::time);
    exception when check_violation or not_null_violation or invalid_datetime_format
              or invalid_text_representation or datetime_field_overflow or unique_violation then
      raise exception 'Invalid working hours' using errcode = '22023';
    end;
  end loop;
  perform public.salon_log(p_shop, v_role, 'staff_hours_set', p_employee, '{}'::jsonb);
end;
$$;

create function public.salon_staff_absence_set(
  p_shop uuid, p_employee uuid, p_day date, p_absent boolean, p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'staff');
begin
  if not exists (select 1 from public.salon_staff_profiles p
                 where p.employee_id = p_employee and p.shop_id = p_shop) or p_day is null then
    raise exception 'Collaborator not found' using errcode = '42501';
  end if;
  if coalesce(p_absent, true) then
    insert into public.salon_staff_absences (shop_id, employee_id, day, reason)
    values (p_shop, p_employee, p_day, nullif(btrim(p_reason), ''))
    on conflict (employee_id, day) do update set reason = excluded.reason;
  else
    delete from public.salon_staff_absences where employee_id = p_employee and day = p_day;
  end if;
  perform public.salon_log(p_shop, v_role, 'staff_absence_set', p_employee,
    jsonb_build_object('day', p_day, 'absent', coalesce(p_absent, true)));
end;
$$;

-- 4. Clients ----------------------------------------------------------------------------------
create function public.salon_clients_search(p_shop uuid, p_query text, p_limit integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'clients');
  v_q text := lower(btrim(coalesce(p_query, '')));
  v_key text := public.salon_phone_key(p_query);
begin
  return coalesce((select jsonb_agg(row_to_json(r)::jsonb) from (
    select c.id, c.first_name, c.last_name, c.phone,
      (select max(a.starts_at) from public.salon_appointments a
        where a.client_id = c.id and a.status = 'completed') as last_visit_at,
      (select count(*) from public.salon_appointments a
        where a.client_id = c.id and a.status = 'completed') as visits
    from public.salon_clients c
    where c.shop_id = p_shop and c.anonymized_at is null
      and (v_q = ''
           or lower(c.first_name || ' ' || coalesce(c.last_name, '')) like '%' || v_q || '%'
           or lower(coalesce(c.last_name, '') || ' ' || c.first_name) like '%' || v_q || '%'
           or (v_key is not null and char_length(v_key) >= 4 and c.phone_key like '%' || v_key || '%'))
    order by c.updated_at desc
    limit greatest(1, least(coalesce(p_limit, 30), 100))) r), '[]'::jsonb);
end;
$$;

create function public.salon_client_save(
  p_shop uuid, p_id uuid, p_first_name text, p_last_name text, p_phone text, p_email text,
  p_preferences text, p_preferences_consent boolean, p_reminder_consent boolean,
  p_force boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'clients');
  v_phone text := nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9+]', '', 'g'), '');
  v_key text := public.salon_phone_key(p_phone);
  v_prefs text := case when coalesce(p_preferences_consent, false) then nullif(btrim(p_preferences), '') end;
  v_dupes jsonb;
  v_id uuid := p_id;
  v_consent_changed boolean;
begin
  if p_first_name is null or char_length(btrim(p_first_name)) not between 1 and 80 then
    raise exception 'First name is required' using errcode = '22023';
  end if;
  -- Doublons probables : même téléphone, ou même prénom + nom. Jamais de fusion automatique.
  select jsonb_agg(jsonb_build_object('id', c.id, 'first_name', c.first_name,
                                      'last_name', c.last_name, 'phone', c.phone))
  into v_dupes
  from public.salon_clients c
  where c.shop_id = p_shop and c.anonymized_at is null and c.id is distinct from v_id
    and ((v_key is not null and c.phone_key = v_key)
         or (lower(btrim(c.first_name)) = lower(btrim(p_first_name))
             and lower(coalesce(btrim(c.last_name), '')) = lower(coalesce(btrim(p_last_name), ''))
             and nullif(btrim(p_last_name), '') is not null));
  if v_dupes is not null and not coalesce(p_force, false) then
    return jsonb_build_object('status', 'possible_duplicate', 'duplicates', v_dupes);
  end if;

  if v_id is null then
    insert into public.salon_clients (shop_id, first_name, last_name, phone, phone_key, email,
      preferences, preferences_consent, reminder_consent, consent_recorded_at, created_by)
    values (p_shop, btrim(p_first_name), nullif(btrim(p_last_name), ''), v_phone, v_key,
      nullif(lower(btrim(p_email)), ''), v_prefs, coalesce(p_preferences_consent, false),
      coalesce(p_reminder_consent, false),
      case when coalesce(p_preferences_consent, false) or coalesce(p_reminder_consent, false)
           then now() end, auth.uid())
    returning id into v_id;
  else
    select (c.preferences_consent, c.reminder_consent)
           is distinct from (coalesce(p_preferences_consent, false), coalesce(p_reminder_consent, false))
    into v_consent_changed
    from public.salon_clients c where c.id = v_id and c.shop_id = p_shop and c.anonymized_at is null;
    if not found then raise exception 'Client not found' using errcode = '42501'; end if;
    update public.salon_clients set first_name = btrim(p_first_name),
      last_name = nullif(btrim(p_last_name), ''), phone = v_phone, phone_key = v_key,
      email = nullif(lower(btrim(p_email)), ''), preferences = v_prefs,
      preferences_consent = coalesce(p_preferences_consent, false),
      reminder_consent = coalesce(p_reminder_consent, false),
      consent_recorded_at = case when v_consent_changed then now() else consent_recorded_at end,
      updated_at = now()
    where id = v_id and shop_id = p_shop;
  end if;
  perform public.salon_log(p_shop, v_role, 'client_saved', v_id, '{}'::jsonb);
  return jsonb_build_object('status', 'ok', 'id', v_id);
end;
$$;

-- Anonymisation (droit à l'effacement) : l'identité disparaît, l'historique chiffré reste.
create function public.salon_client_anonymize(p_shop uuid, p_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := public.salon_require(p_shop, 'clients_admin');
begin
  update public.salon_clients set first_name = 'Client', last_name = 'anonymisé', phone = null,
    phone_key = null, email = null, preferences = null, preferences_consent = false,
    reminder_consent = false, anonymized_at = now(), updated_at = now()
  where id = p_id and shop_id = p_shop and anonymized_at is null;
  if not found then raise exception 'Client not found' using errcode = '42501'; end if;
  perform public.salon_log(p_shop, v_role, 'client_anonymized', p_id, '{}'::jsonb);
end;
$$;

revoke all on function
  public.salon_settings_get(uuid),
  public.salon_settings_save(uuid, text, text, text, integer, text, jsonb),
  public.salon_catalog(uuid),
  public.salon_service_save(uuid, uuid, text, text, text, bigint, integer, bigint, boolean, uuid[]),
  public.salon_staff_list(uuid),
  public.salon_staff_save(uuid, uuid, text, text, text, text, numeric, bigint, text, boolean, uuid[]),
  public.salon_staff_hours_set(uuid, uuid, jsonb),
  public.salon_staff_absence_set(uuid, uuid, date, boolean, text),
  public.salon_client_anonymize(uuid, uuid)
  from public, anon;
grant execute on function
  public.salon_settings_get(uuid),
  public.salon_settings_save(uuid, text, text, text, integer, text, jsonb),
  public.salon_catalog(uuid),
  public.salon_service_save(uuid, uuid, text, text, text, bigint, integer, bigint, boolean, uuid[]),
  public.salon_staff_list(uuid),
  public.salon_staff_save(uuid, uuid, text, text, text, text, numeric, bigint, text, boolean, uuid[]),
  public.salon_staff_hours_set(uuid, uuid, jsonb),
  public.salon_staff_absence_set(uuid, uuid, date, boolean, text),
  public.salon_client_anonymize(uuid, uuid)
  to authenticated;
