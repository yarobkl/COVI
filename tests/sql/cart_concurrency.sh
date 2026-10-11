#!/usr/bin/env bash
# Concurrence de record_cart_sale, avec deux vraies sessions psql (lancé par tests/sql/run.sh).
#
# Les tests .sql tournent dans une seule session : ils ne peuvent pas montrer ce qui se passe
# quand deux caisses valident en même temps. Ici, la session 1 ouvre une transaction, enregistre
# son panier (ses lignes produits restent verrouillées) et attend un signal ; la session 2 lance
# son panier et se bloque. On vérifie dans pg_stat_activity que la session 2 attend bien un
# verrou, puis on libère la session 1 (COMMIT) et on contrôle le résultat. Déterministe : aucun
# sleep « au hasard ».
#
# Scénarios :
#   1. deux paniers sur la dernière pièce : un seul passe, l'autre reçoit une erreur définitive ;
#   2. même client_operation_id envoyé deux fois en parallèle : une seule vente, un seul décrément ;
#   3. deux paniers qui partagent deux produits, listés en ordre inverse : les deux passent,
#      sans interblocage (verrouillage dans l'ordre des id).
#
# Les fixtures sont validées (COMMIT, nécessaire pour être vues par deux sessions) puis
# supprimées à la fin, même en cas d'échec.
#
# Variables : COVI_TEST_DB (défaut covi_test) et PGHOST/PGPORT/PGUSER/PGPASSWORD.
set -euo pipefail

db="${COVI_TEST_DB:-covi_test}"
work="$(mktemp -d "${TMPDIR:-/tmp}/covi-cart.XXXXXX")"
chmod 777 "$work"

psql_db() { psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }

shop='10000000-0000-0000-0000-0000000000e1'
user='00000000-0000-0000-0000-0000000000e1'
last_piece='30000000-0000-0000-0000-0000000000e1'
p_low='30000000-0000-0000-0000-0000000000e2'
p_high='30000000-0000-0000-0000-0000000000e3'
p_idem='30000000-0000-0000-0000-0000000000e4'

cleanup() {
  psql_db -c "delete from public.sale_items where sale_id in
                (select id from public.sales where shop_id = '$shop');
              delete from public.sales where shop_id = '$shop';
              delete from public.products where shop_id = '$shop';
              delete from public.shops where id = '$shop';
              delete from auth.users where id = '$user';" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "ok  $*"; }

cleanup_data_only() {
  psql_db -c "delete from public.sale_items where sale_id in
                (select id from public.sales where shop_id = '$shop');
              delete from public.sales where shop_id = '$shop';" >/dev/null
}

psql_db >/dev/null <<SQL
insert into auth.users(id) values ('$user');
insert into public.shops(id, owner_id, name) values ('$shop', '$user', 'Boutique concurrence');
insert into public.products(id, shop_id, name, initial_sale_price, quantity_on_hand, is_unique_piece)
values ('$last_piece', '$shop', 'Dernière pièce', 10000, 1, true),
       ('$p_low',      '$shop', 'Produit bas',     1000, 2, false),
       ('$p_high',     '$shop', 'Produit haut',    2000, 2, false),
       ('$p_idem',     '$shop', 'Produit idem',    3000, 5, false);
SQL

# Session 1 : panier dans une transaction ouverte, COMMIT seulement quand le fichier go existe.
# Session 2 : même chose sans attente ; elle doit se bloquer derrière la session 1.
# $1 = étiquette, $2 = items de la session 1, $3 = op id 1, $4 = items session 2, $5 = op id 2
run_pair() {
  local label="$1" items1="$2" op1="$3" items2="$4" op2="$5"
  rm -f "$work/go"
  psql_db -At -v ON_ERROR_STOP=0 >"$work/s1.out" 2>&1 <<SQL &
set application_name = 'covi-cart-s1';
set request.jwt.claim.sub = '$user';
set role authenticated;
begin;
select 'sale:' || public.record_cart_sale('$shop', '$items1', 'cash', '$op1');
\! while [ ! -f '$work/go' ]; do sleep 0.05; done
commit;
SQL
  local s1=$!

  # Attendre que la session 1 tienne ses verrous (elle est entrée dans l'attente du signal).
  for _ in $(seq 1 200); do
    [[ "$(psql_db -At -c "select count(*) from pg_stat_activity
           where application_name = 'covi-cart-s1' and state = 'idle in transaction'")" == "1" ]] && break
    sleep 0.05
  done
  [[ "$(psql_db -At -c "select count(*) from pg_stat_activity
         where application_name = 'covi-cart-s1' and state = 'idle in transaction'")" == "1" ]] \
    || { touch "$work/go"; wait "$s1" || true; cat "$work/s1.out" >&2; fail "$label : session 1 pas prête"; }

  psql_db -At -v ON_ERROR_STOP=0 >"$work/s2.out" 2>&1 <<SQL &
set application_name = 'covi-cart-s2';
set request.jwt.claim.sub = '$user';
set role authenticated;
select 'sale:' || public.record_cart_sale('$shop', '$items2', 'cash', '$op2');
SQL
  local s2=$!

  # La session 2 doit attendre un verrou (ligne produit ou verrou consultatif).
  local waiting=""
  for _ in $(seq 1 200); do
    waiting="$(psql_db -At -c "select wait_event_type from pg_stat_activity
                where application_name = 'covi-cart-s2' and wait_event_type = 'Lock'")"
    [[ -n "$waiting" ]] && break
    sleep 0.05
  done
  touch "$work/go"
  wait "$s1" || true
  wait "$s2" || true
  [[ -n "$waiting" ]] || { cat "$work/s1.out" "$work/s2.out" >&2; fail "$label : la session 2 n'a pas attendu de verrou"; }
  ok "$label : la session 2 a attendu le verrou de la session 1"
}

item() { printf '{"product_id":"%s","quantity":%s,"sold_unit_price":%s}' "$1" "$2" "$3"; }

# 1. Dernière pièce ---------------------------------------------------------------------------
run_pair "dernière pièce" \
  "[$(item "$p_low" 1 1000),$(item "$last_piece" 1 10000)]" '40000000-0000-0000-0000-0000000000e1' \
  "[$(item "$last_piece" 1 9500)]"                          '40000000-0000-0000-0000-0000000000e2'
grep -q '^sale:' "$work/s1.out" || { cat "$work/s1.out" >&2; fail "dernière pièce : la session 1 aurait dû vendre"; }
grep -q 'Product unavailable' "$work/s2.out" || { cat "$work/s2.out" >&2; fail "dernière pièce : la session 2 aurait dû être refusée"; }
[[ "$(psql_db -At -c "select count(*) from public.sale_items where product_id = '$last_piece'")" == "1" ]] \
  || fail "dernière pièce : vendue plus d'une fois"
[[ "$(psql_db -At -c "select quantity_on_hand || ':' || status from public.products where id = '$last_piece'")" == "0:sold" ]] \
  || fail "dernière pièce : stock final incorrect"
[[ "$(psql_db -At -c "select count(*) from public.sales where shop_id = '$shop'")" == "1" ]] \
  || fail "dernière pièce : le panier refusé a laissé une vente"
[[ "$(psql_db -At -c "select quantity_on_hand from public.products where id = '$p_low'")" == "1" ]] \
  || fail "dernière pièce : stock de l'autre ligne incorrect"
ok "dernière pièce : un seul panier passe, l'autre reçoit 'Product unavailable' sans rien écrire"

# 2. Même operation id en parallèle ------------------------------------------------------------
cleanup_data_only
op='40000000-0000-0000-0000-0000000000e3'
run_pair "même operation id" "[$(item "$p_idem" 2 3000)]" "$op" "[$(item "$p_idem" 2 3000)]" "$op"
id1="$(sed -n 's/^sale://p' "$work/s1.out")"
id2="$(sed -n 's/^sale://p' "$work/s2.out")"
[[ -n "$id1" && "$id1" == "$id2" ]] || { cat "$work/s1.out" "$work/s2.out" >&2; fail "même operation id : ids différents"; }
[[ "$(psql_db -At -c "select count(*) from public.sales where client_operation_id = '$op'")" == "1" ]] \
  || fail "même operation id : plusieurs ventes"
[[ "$(psql_db -At -c "select quantity_on_hand from public.products where id = '$p_idem'")" == "3" ]] \
  || fail "même operation id : stock décrémenté deux fois"
ok "même operation id : une seule vente, même id renvoyé aux deux sessions, un seul décrément"

# 3. Ordre inverse, pas d'interblocage ----------------------------------------------------------
cleanup_data_only
psql_db -c "update public.products set quantity_on_hand = 2, status = 'active'
            where id in ('$p_low', '$p_high')" >/dev/null
run_pair "ordre inverse" \
  "[$(item "$p_high" 1 2000),$(item "$p_low" 1 1000)]" '40000000-0000-0000-0000-0000000000e4' \
  "[$(item "$p_low" 1 1000),$(item "$p_high" 1 2000)]" '40000000-0000-0000-0000-0000000000e5'
grep -q '^sale:' "$work/s1.out" && grep -q '^sale:' "$work/s2.out" \
  || { cat "$work/s1.out" "$work/s2.out" >&2; fail "ordre inverse : les deux paniers auraient dû passer"; }
grep -qi 'deadlock' "$work/s1.out" "$work/s2.out" && fail "ordre inverse : interblocage"
[[ "$(psql_db -At -c "select string_agg(quantity_on_hand || ':' || status, ',' order by name)
       from public.products where id in ('$p_low', '$p_high')")" == "0:sold,0:sold" ]] \
  || fail "ordre inverse : stocks finaux incorrects"
ok "ordre inverse : les deux paniers passent l'un après l'autre, sans interblocage"
