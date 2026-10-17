#!/usr/bin/env bash
# Test de concurrence restaurant : deux appareils essayent d'ouvrir la même table.
# Banque PostgreSQL temporaire créée par tests/sql/run.sh uniquement.
set -euo pipefail
db="${COVI_TEST_DB:-covi_test}"
dir="$(mktemp -d "${TMPDIR:-/tmp}/covi-restaurant.XXXXXX")"
chmod 777 "$dir"
psql_db(){ psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
owner='00000000-0000-0000-0000-0000000000e7'
shop='10000000-0000-0000-0000-0000000000e7'
table_id='20000000-0000-0000-0000-0000000000e7'
clean(){
  touch "$dir/release" 2>/dev/null || true
  psql_db -c "delete from public.restaurant_participants where shop_id='$shop';
    delete from public.restaurant_session_lines where shop_id='$shop';
    delete from public.restaurant_cash_payments where shop_id='$shop';
    delete from public.restaurant_table_sessions where shop_id='$shop';
    delete from public.restaurant_tables where shop_id='$shop';
    delete from public.shops where id='$shop';
    delete from auth.users where id='$owner';" >/dev/null 2>&1 || true
  rm -rf "$dir"
}
trap clean EXIT
fail(){ echo "FAIL restaurant-concurrency: $*" >&2; exit 1; }
psql_db >/dev/null <<SQL
insert into auth.users(id) values('$owner');
insert into public.shops(id,owner_id,name,business_kind)
values('$shop','$owner','Restaurant concurrence','restaurant');
insert into public.restaurant_tables(id,shop_id,label,capacity)
values('$table_id','$shop','09',4);
SQL

# Transaction A garde le verrou sur la table pendant que B tente d'ouvrir une session.
psql_db -At -v ON_ERROR_STOP=0 >"$dir/a.out" 2>&1 <<SQL &
set application_name='covi-rest-a';
set request.jwt.claim.sub='$owner';
set role authenticated;
begin;
select public.restaurant_open_table('$shop','$table_id',2);
\! while [ ! -f '$dir/release' ]; do sleep 0.05; done
commit;
SQL
pid_a=$!
for _ in $(seq 1 150); do
  [[ "$(psql_db -At -c "select count(*) from pg_stat_activity where application_name='covi-rest-a' and state='idle in transaction'")" == "1" ]] && break
  sleep 0.05
done
[[ "$(psql_db -At -c "select count(*) from pg_stat_activity where application_name='covi-rest-a' and state='idle in transaction'")" == "1" ]] || { touch "$dir/release"; wait "$pid_a" || true; fail 'terminal A non prêt'; }

psql_db -At -v ON_ERROR_STOP=0 >"$dir/b.out" 2>&1 <<SQL &
set application_name='covi-rest-b';
set request.jwt.claim.sub='$owner';
set role authenticated;
select public.restaurant_open_table('$shop','$table_id',3);
SQL
pid_b=$!
waiting=''
for _ in $(seq 1 150); do
  waiting="$(psql_db -At -c "select wait_event_type from pg_stat_activity where application_name='covi-rest-b' and wait_event_type='Lock'")"
  [[ -n "$waiting" ]] && break
  sleep 0.05
done
touch "$dir/release"
wait "$pid_a" || true
wait "$pid_b" || true
[[ -n "$waiting" ]] || { cat "$dir/a.out" "$dir/b.out" >&2; fail 'second appareil non sérialisé'; }
grep -q 'Table occupied' "$dir/b.out" || { cat "$dir/b.out" >&2; fail 'deuxième tablée non rejetée'; }
[[ "$(psql_db -At -c "select count(*) from public.restaurant_table_sessions where shop_id='$shop' and status='collecting'")" == '1' ]] || fail 'plusieurs sessions sur une table'
echo 'ok  deux appareils concurrents : une seule session de table, seconde requête refusée'
