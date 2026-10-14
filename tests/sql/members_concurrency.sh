#!/usr/bin/env bash
# Concurrence caisse multi-caissiers, avec deux vraies sessions psql (lancé par tests/sql/run.sh).
#
# Scénario : dernière pièce disputée par deux caisses de la même boutique :
#   - session 1 : caissière C1 sur SON compte (record_sale), transaction ouverte jusqu'au signal ;
#   - session 2 : appareil partagé du PROPRIÉTAIRE avec une session de caisse de C2
#     (record_cart_sale + p_till_session) ; elle doit attendre le verrou de la session 1.
# Résultat attendu : une seule vente (celle de C1, seller_id = C1), la session 2 reçoit
# 'Product unavailable', stock 0 / 'sold', aucune vente écrite pour la session 2.
#
# Fixtures : données fictives validées (COMMIT) puis supprimées à la fin, même en cas d'échec.
set -euo pipefail

db="${COVI_TEST_DB:-covi_test}"
work="$(mktemp -d "${TMPDIR:-/tmp}/covi-members.XXXXXX")"
chmod 777 "$work"

psql_db() { psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }

shop='10000000-0000-0000-0000-0000000000f1'
owner='00000000-0000-0000-0000-0000000000f1'
c1='00000000-0000-0000-0000-0000000000f2'
c2='00000000-0000-0000-0000-0000000000f3'
m1='50000000-0000-0000-0000-0000000000f2'
m2='50000000-0000-0000-0000-0000000000f3'
piece='30000000-0000-0000-0000-0000000000f1'
token="$(printf 'f%.0s' $(seq 1 64))"

cleanup() {
  psql_db -c "delete from public.sale_items where sale_id in
                (select id from public.sales where shop_id = '$shop');
              delete from public.sales where shop_id = '$shop';
              delete from public.products where shop_id = '$shop';
              delete from public.shops where id = '$shop';
              delete from auth.users where id in ('$owner', '$c1', '$c2');" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "ok  $*"; }

psql_db >/dev/null <<SQL
insert into auth.users(id) values ('$owner'), ('$c1'), ('$c2');
insert into public.shops(id, owner_id, name) values ('$shop', '$owner', 'Boutique concurrence caisse');
insert into public.shop_members(id, shop_id, user_id, display_name, max_discount_pct) values
  ('$m1', '$shop', '$c1', 'C1', 0), ('$m2', '$shop', '$c2', 'C2', 10);
insert into public.member_pins(member_id, pin_hash) values
  ('$m1', extensions.crypt('4826', extensions.gen_salt('bf', 10))),
  ('$m2', extensions.crypt('6284', extensions.gen_salt('bf', 10)));
insert into public.till_sessions(shop_id, member_id, token_hash, opened_by, expires_at) values
  ('$shop', '$m2', sha256(convert_to('covi-till:$token', 'UTF8')), '$owner', now() + interval '1 hour');
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand, is_unique_piece)
values ('$piece', '$shop', 'Dernière veste', 20000, 1, true);
SQL

rm -f "$work/go"
psql_db -At -v ON_ERROR_STOP=0 >"$work/s1.out" 2>&1 <<SQL &
set application_name = 'covi-members-s1';
set request.jwt.claim.sub = '$c1';
set role authenticated;
begin;
select 'sale:' || public.record_sale('$shop', '$piece', 1, 20000, 'cash',
                                     '40000000-0000-0000-0000-0000000000f1');
\! while [ ! -f '$work/go' ]; do sleep 0.05; done
commit;
SQL
s1=$!

for _ in $(seq 1 200); do
  [[ "$(psql_db -At -c "select count(*) from pg_stat_activity
         where application_name = 'covi-members-s1' and state = 'idle in transaction'")" == "1" ]] && break
  sleep 0.05
done
[[ "$(psql_db -At -c "select count(*) from pg_stat_activity
       where application_name = 'covi-members-s1' and state = 'idle in transaction'")" == "1" ]] \
  || { touch "$work/go"; wait "$s1" || true; cat "$work/s1.out" >&2; fail "session 1 pas prête"; }

psql_db -At -v ON_ERROR_STOP=0 >"$work/s2.out" 2>&1 <<SQL &
set application_name = 'covi-members-s2';
set request.jwt.claim.sub = '$owner';
set role authenticated;
select 'sale:' || public.record_cart_sale('$shop',
  '[{"product_id":"$piece","quantity":1,"sold_unit_price":18000}]', 'cash',
  '40000000-0000-0000-0000-0000000000f2', p_till_session => '$token');
SQL
s2=$!

waiting=""
for _ in $(seq 1 200); do
  waiting="$(psql_db -At -c "select wait_event_type from pg_stat_activity
              where application_name = 'covi-members-s2' and wait_event_type = 'Lock'")"
  [[ -n "$waiting" ]] && break
  sleep 0.05
done
touch "$work/go"
wait "$s1" || true
wait "$s2" || true
[[ -n "$waiting" ]] || { cat "$work/s1.out" "$work/s2.out" >&2; fail "la session 2 n'a pas attendu de verrou"; }
ok "la session de caisse du propriétaire a attendu le verrou de la caissière"

grep -q '^sale:' "$work/s1.out" || { cat "$work/s1.out" >&2; fail "C1 aurait dû vendre"; }
grep -q 'Product unavailable' "$work/s2.out" || { cat "$work/s2.out" >&2; fail "la session 2 aurait dû être refusée"; }
[[ "$(psql_db -At -c "select count(*) || ':' || min(seller_id::text) from public.sales where shop_id = '$shop'")" == "1:$c1" ]] \
  || fail "une seule vente attendue, attribuée à C1"
[[ "$(psql_db -At -c "select quantity_on_hand || ':' || status from public.products where id = '$piece'")" == "0:sold" ]] \
  || fail "stock final incorrect"
ok "dernière pièce entre deux caissiers : une seule vente (C1), l'autre reçoit 'Product unavailable', stock 0/sold"
