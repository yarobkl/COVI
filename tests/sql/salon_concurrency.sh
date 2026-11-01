#!/usr/bin/env bash
# Salon : deux appareils en même temps (lancé par tests/sql/run.sh).
#   1. même coiffeur, même créneau, deux réservations simultanées : une seule passe ;
#   2. même ticket encaissé deux fois en parallèle avec deux clés différentes : un seul paiement,
#      le stock n'est décrémenté qu'une fois.
# La session 1 garde sa transaction ouverte (pg_sleep) ; on vérifie dans pg_stat_activity que la
# session 2 attend bien un verrou avant de laisser la session 1 valider.
set -euo pipefail

db="${COVI_TEST_DB:-covi_test}"
work="$(mktemp -d "${TMPDIR:-/tmp}/covi-salon.XXXXXX")"
chmod 777 "$work"
psql_db() { psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }

shop='10000000-0000-0000-0000-0000000000c1'
owner='00000000-0000-0000-0000-0000000000c1'
staff='40000000-0000-0000-0000-0000000000c1'
svc='20000000-0000-0000-0000-0000000000c1'
oil='50000000-0000-0000-0000-0000000000c1'

cleanup() {
  psql_db >/dev/null 2>&1 <<SQL || true
delete from public.salon_payments where shop_id = '$shop';
delete from public.salon_supply_movements where shop_id = '$shop';
delete from public.salon_ticket_lines where shop_id = '$shop';
delete from public.salon_tickets where shop_id = '$shop';
delete from public.salon_appointment_services where shop_id = '$shop';
delete from public.salon_appointments where shop_id = '$shop';
delete from public.salon_events where shop_id = '$shop';
delete from public.salon_opening_hours where shop_id = '$shop';
delete from public.shops where id = '$shop';
delete from auth.users where id = '$owner';
SQL
  rm -rf "$work"
}
trap cleanup EXIT
fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "ok  $*"; }

as_owner="select set_config('request.jwt.claim.sub', '$owner', false);"

psql_db >/dev/null <<SQL
insert into auth.users(id) values ('$owner');
insert into public.shops(id, owner_id, name, business_kind) values ('$shop', '$owner', 'Salon concurrence', 'salon');
insert into public.employees(id, shop_id, full_name, job_title) values ('$staff', '$shop', 'Coiffeur C', 'Coiffeur');
insert into public.salon_staff_profiles(employee_id, shop_id) values ('$staff', '$shop');
insert into public.salon_services(id, shop_id, name, price_xaf, duration_minutes) values ('$svc', '$shop', 'Coupe', 10000, 60);
insert into public.salon_supplies(id, shop_id, name, unit, usage, quantity_on_hand, sale_price_xaf)
  values ('$oil', '$shop', 'Huile', 'piece', 'sale', 1, 5000);
-- The test probes concurrency within actual opening hours, not an unconfigured salon.
insert into public.salon_opening_hours (shop_id, weekday, opens_at, closes_at)
select '$shop', d::smallint, '08:00'::time, '20:00'::time from generate_series(1, 7) d;
SQL

wait_for_lock() {
  for _ in $(seq 1 100); do
    n=$(psql_db -At -c "select count(*) from pg_stat_activity where datname = current_database()
                         and wait_event_type = 'Lock' and query like '%$1%'")
    [[ "$n" -ge 1 ]] && return 0
    sleep 0.1
  done
  return 1
}

# 1. Réservations simultanées -------------------------------------------------------------------
slot="(((now() at time zone 'Africa/Brazzaville')::date + 2) + time '10:00') at time zone 'Africa/Brazzaville'"
book() { echo "$as_owner begin; select public.salon_appointment_save('$shop', null, null, '$1', null, '$staff', $slot, array['$svc']::uuid[], null, null) as booked_$1; $2 commit;"; }
(set +e; psql -X -q -v ON_ERROR_STOP=1 -d "$db" -c "$(book un 'select pg_sleep(2);')" >"$work/b1.out" 2>&1; echo $? >"$work/b1.rc") &
p1=$!
sleep 0.3
(set +e; psql -X -q -v ON_ERROR_STOP=1 -d "$db" -c "$(book deux '')" >"$work/b2.out" 2>&1; echo $? >"$work/b2.rc") &
p2=$!
wait_for_lock booked_deux || fail "la 2e réservation n'attend pas le verrou de l'agenda"
wait $p1 $p2 || true
[[ "$(cat "$work/b1.rc")" == "0" ]] || fail "réservation 1 refusée : $(cat "$work/b1.out")"
[[ "$(cat "$work/b2.rc")" != "0" ]] || fail "réservation 2 acceptée : double réservation"
grep -q "already booked" "$work/b2.out" || fail "message attendu absent : $(cat "$work/b2.out")"
n=$(psql_db -At -c "select count(*) from public.salon_appointments where shop_id = '$shop'")
[[ "$n" == "1" ]] || fail "$n rendez-vous au lieu de 1"
ok "réservations simultanées du même créneau : une seule acceptée"

# 2. Encaissements simultanés du même ticket ------------------------------------------------------
ticket=$(psql_db -At -c "$as_owner select public.salon_ticket_open('$shop', null, null, 'Client', 'conc-ticket-0001') ->> 'id'" | tail -1)
psql_db -At -c "$as_owner select public.salon_ticket_add_line('$shop', '$ticket', 'product', '$oil', null, 1, null)" >/dev/null
pay() { echo "$as_owner begin; select public.salon_ticket_pay('$shop', '$ticket', '[{\"method\":\"cash\",\"amount_xaf\":5000}]'::jsonb, '$1') as paid_$2; $3 commit;"; }
(set +e; psql -X -q -v ON_ERROR_STOP=1 -d "$db" -c "$(pay conc-pay-00001 un 'select pg_sleep(2);')" >"$work/p1.out" 2>&1; echo $? >"$work/p1.rc") &
p1=$!
sleep 0.3
(set +e; psql -X -q -v ON_ERROR_STOP=1 -d "$db" -c "$(pay conc-pay-00002 deux '')" >"$work/p2.out" 2>&1; echo $? >"$work/p2.rc") &
p2=$!
wait_for_lock paid_deux || fail "le 2e encaissement n'attend pas le verrou du ticket"
wait $p1 $p2 || true
[[ "$(cat "$work/p1.rc")" == "0" ]] || fail "encaissement 1 refusé : $(cat "$work/p1.out")"
[[ "$(cat "$work/p2.rc")" != "0" ]] || fail "encaissement 2 accepté"
n=$(psql_db -At -c "select count(*) || '/' || coalesce(sum(amount_xaf), 0) from public.salon_payments where shop_id = '$shop'")
[[ "$n" == "1/5000" ]] || fail "paiements : $n au lieu de 1/5000"
q=$(psql_db -At -c "select quantity_on_hand::int from public.salon_supplies where id = '$oil'")
[[ "$q" == "0" ]] || fail "stock $q au lieu de 0"
ok "encaissements simultanés : un seul paiement, stock décrémenté une fois"
