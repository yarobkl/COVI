-- Safety regression: a salon without opening hours must not accept appointments.
-- All writes are inside a transaction rolled back after the test.
\set ON_ERROR_STOP 1
begin;

insert into auth.users(id) values ('00000000-0000-0000-0000-00000000a061');
insert into public.shops(id, owner_id, name, business_kind)
values ('10000000-0000-0000-0000-00000000a061', '00000000-0000-0000-0000-00000000a061', 'Salon heures fermées', 'salon');

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000a061', true);
set local role authenticated;

do $checks$
declare
  v_shop uuid := '10000000-0000-0000-0000-00000000a061';
  v_employee uuid;
  v_service uuid;
  v_day date := (now() at time zone 'Africa/Brazzaville')::date + 2;
  v_start timestamptz;
  v_id uuid;
begin
  v_employee := public.salon_staff_save(
    v_shop, null, 'Nina Test', 'Coiffeuse', null, 'none', 0, 0, '#17408b', true, null
  );
  v_service := public.salon_service_save(
    v_shop, null, 'Coupe', 'Coiffure', null, 5000, 60, 0, true, array[v_employee]
  );
  v_start := (v_day + time '10:00') at time zone 'Africa/Brazzaville';

  -- No settings saved: no opening slot must mean closed.
  begin
    perform public.salon_appointment_save(
      v_shop, null, null, 'Client avant réglages', null, v_employee, v_start,
      array[v_service], null, null
    );
    raise exception 'FAIL: unconfigured salon accepted a reservation';
  exception when sqlstate '22023' then
    null;
  end;

  -- Explicitly save zero open days, not a missing network payload.
  perform public.salon_settings_save(v_shop, 'mixed', null, null, null,
    'Africa/Brazzaville', '[]'::jsonb);
  begin
    perform public.salon_appointment_save(
      v_shop, null, null, 'Client malgré fermeture', null, v_employee, v_start,
      array[v_service], null, null
    );
    raise exception 'FAIL: salon closed all week accepted a reservation';
  exception when sqlstate '22023' then
    null;
  end;

  -- Explicitly open 08:00-18:00: normal appointment must still work.
  perform public.salon_settings_save(v_shop, 'mixed', null, null, null, 'Africa/Brazzaville',
    (select jsonb_agg(jsonb_build_object(
      'weekday', d, 'opens_at', '08:00', 'closes_at', '18:00'
    )) from generate_series(1, 7) d));
  v_id := public.salon_appointment_save(
    v_shop, null, null, 'Client heures ouvertes', null, v_employee, v_start,
    array[v_service], null, null
  );
  if v_id is null then
    raise exception 'FAIL: correctly scheduled appointment was rejected';
  end if;

  -- End exactly at midnight must not bypass the previous day's closing hour.
  perform public.salon_settings_save(v_shop, 'mixed', null, null, null, 'Africa/Brazzaville',
    (select jsonb_agg(jsonb_build_object(
      'weekday', d, 'opens_at', '08:00', 'closes_at', '23:00'
    )) from generate_series(1, 7) d));
  begin
    perform public.salon_appointment_save(
      v_shop, null, null, 'Client à minuit', null, v_employee,
      (v_day + time '23:00') at time zone 'Africa/Brazzaville',
      array[v_service], null, null
    );
    raise exception 'FAIL: midnight overrun accepted after shop closing';
  exception when sqlstate '22023' then
    null;
  end;
end;
$checks$;

rollback;
