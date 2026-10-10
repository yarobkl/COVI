#!/usr/bin/env bash
# Concurrence des fonctions SaaS (PR #12), avec deux vraies sessions psql (lancé par run.sh).
#
# Même mécanique que cart_concurrency.sh : la session 1 ouvre une transaction, exécute son
# appel et attend un signal avant COMMIT ; la session 2 lance le même type d'appel et doit
# attendre un verrou (vérifié dans pg_stat_activity), puis on libère la session 1.
#
# Scénarios :
#   1. double confirmation simultanée de la même facture : un seul paiement, l'autre refusé ;
#   2. même référence Mobile Money sur deux factures différentes en parallèle : une seule passe ;
#   3. quota 2 avec 1 boutique existante, deux créations simultanées : une seule réussit ;
#   4. commerçant V1 sans abonnement, deux créations simultanées : une seule boutique.
set -euo pipefail

db="${COVI_TEST_DB:-covi_test}"
work="$(mktemp -d "${TMPDIR:-/tmp}/covi-saas.XXXXXX")"
chmod 777 "$work"

psql_db() { psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }

admin='00000000-0000-0000-0000-0000000000f0'
o1='00000000-0000-0000-0000-0000000000f1'
o2='00000000-0000-0000-0000-0000000000f2'
legacy='00000000-0000-0000-0000-0000000000f3'
users="'$admin','$o1','$o2','$legacy'"

cleanup() {
  psql_db -c "delete from public.covi_subscription_audit where owner_account_id in
                (select id from public.covi_owner_accounts where user_id in ($users));
              delete from public.covi_subscription_payments where invoice_id in
                (select i.id from public.covi_subscription_invoices i
                 join public.covi_subscriptions s on s.id = i.subscription_id
                 join public.covi_owner_accounts a on a.id = s.owner_account_id
                 where a.user_id in ($users));
              delete from public.covi_subscription_invoices where subscription_id in
                (select s.id from public.covi_subscriptions s
                 join public.covi_owner_accounts a on a.id = s.owner_account_id
                 where a.user_id in ($users));
              delete from public.covi_subscriptions where owner_account_id in
                (select id from public.covi_owner_accounts where user_id in ($users));
              delete from public.covi_owner_accounts where user_id in ($users);
              delete from public.covi_platform_admins where user_id in ($users);
              delete from public.shops where owner_id in ($users);
              delete from auth.users where id in ($users);" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "ok  $*"; }

# Exécute une requête en tant qu'utilisateur authentifié et renvoie la première valeur.
as_user() { psql_db -At -c "set request.jwt.claim.sub = '$1'; set role authenticated; $2" | tail -n 1; }

# $1 = étiquette, $2 = utilisateur s1, $3 = SQL s1, $4 = utilisateur s2, $5 = SQL s2
run_pair() {
  local label="$1" u1="$2" sql1="$3" u2="$4" sql2="$5"
  rm -f "$work/go"
  psql_db -At -v ON_ERROR_STOP=0 >"$work/s1.out" 2>&1 <<SQL &
set application_name = 'covi-saas-s1';
set request.jwt.claim.sub = '$u1';
set role authenticated;
begin;
select 'res:' || ($sql1);
\! while [ ! -f '$work/go' ]; do sleep 0.05; done
commit;
SQL
  local s1=$!
  for _ in $(seq 1 200); do
    [[ "$(psql_db -At -c "select count(*) from pg_stat_activity
           where application_name = 'covi-saas-s1' and state = 'idle in transaction'")" == "1" ]] && break
    sleep 0.05
  done
  [[ "$(psql_db -At -c "select count(*) from pg_stat_activity
         where application_name = 'covi-saas-s1' and state = 'idle in transaction'")" == "1" ]] \
    || { touch "$work/go"; wait "$s1" || true; cat "$work/s1.out" >&2; fail "$label : session 1 pas prête"; }

  psql_db -At -v ON_ERROR_STOP=0 >"$work/s2.out" 2>&1 <<SQL &
set application_name = 'covi-saas-s2';
set request.jwt.claim.sub = '$u2';
set role authenticated;
select 'res:' || ($sql2);
SQL
  local s2=$!
  local waiting=""
  for _ in $(seq 1 200); do
    waiting="$(psql_db -At -c "select wait_event_type from pg_stat_activity
                where application_name = 'covi-saas-s2' and wait_event_type = 'Lock'")"
    [[ -n "$waiting" ]] && break
    sleep 0.05
  done
  touch "$work/go"
  wait "$s1" || true
  wait "$s2" || true
  [[ -n "$waiting" ]] || { cat "$work/s1.out" "$work/s2.out" >&2; fail "$label : la session 2 n'a pas attendu de verrou"; }
  ok "$label : la session 2 a attendu le verrou de la session 1"
  echo "   s1: $(grep -E 'res:|ERROR' "$work/s1.out" | head -n 1)"
  echo "   s2: $(grep -E 'res:|ERROR' "$work/s2.out" | head -n 1)"
}

psql_db >/dev/null <<SQL
insert into auth.users(id) values ('$admin'), ('$o1'), ('$o2'), ('$legacy');
insert into public.covi_platform_admins(user_id) values ('$admin');
SQL

issue() { # $1 = owner, $2 = numéro, $3 = quota
  as_user "$admin" "select public.covi_admin_issue_subscription_invoice('$1', '$2', $3,
                      now() - interval '1 hour', now() + interval '30 days')"
}

# 1. Double confirmation simultanée ----------------------------------------------------------
inv1="$(issue "$o1" CONC-0001 2)"
[[ -n "$inv1" ]] || fail "facture 1 non émise"
run_pair "double confirmation" \
  "$admin" "select public.covi_admin_confirm_mobile_payment('$inv1', 'MTN Mobile Money', 'MP-CONC-1', 15000)::text" \
  "$admin" "select public.covi_admin_confirm_mobile_payment('$inv1', 'MTN Mobile Money', 'MP-CONC-2', 15000)::text"
grep -q '^res:' "$work/s1.out" || { cat "$work/s1.out" >&2; fail "double confirmation : s1 aurait dû passer"; }
grep -q 'Invoice not pending' "$work/s2.out" || { cat "$work/s2.out" >&2; fail "double confirmation : s2 aurait dû être refusée"; }
[[ "$(psql_db -At -c "select count(*) from public.covi_subscription_payments where invoice_id = '$inv1'")" == "1" ]] \
  || fail "double confirmation : plusieurs paiements"
ok "double confirmation : un seul paiement, la 2e session reçoit 'Invoice not pending'"

# 2. Même référence sur deux factures en parallèle --------------------------------------------
inv2="$(issue "$o2" CONC-0002 1)"
[[ -n "$inv2" ]] || fail "facture 2 non émise"
# o1 a besoin d'une nouvelle facture : abonnement actif, on suspend puis on refacture.
sub1="$(psql_db -At -c "select s.id from public.covi_subscriptions s join public.covi_owner_accounts a
                         on a.id = s.owner_account_id where a.user_id = '$o1'")"
as_user "$admin" "select public.covi_admin_suspend_subscription('$sub1', 'test de concurrence')" >/dev/null
inv3="$(issue "$o1" CONC-0003 2)"
run_pair "même référence MoMo" \
  "$admin" "select public.covi_admin_confirm_mobile_payment('$inv3', 'MTN Mobile Money', 'MP-CONC-DUP', 15000)::text" \
  "$admin" "select public.covi_admin_confirm_mobile_payment('$inv2', 'MTN Mobile Money', 'MP-CONC-DUP', 10000)::text"
grep -q '^res:' "$work/s1.out" || { cat "$work/s1.out" >&2; fail "même référence : s1 aurait dû passer"; }
grep -q 'duplicate key' "$work/s2.out" || { cat "$work/s2.out" >&2; fail "même référence : s2 aurait dû être refusée"; }
[[ "$(psql_db -At -c "select count(*) from public.covi_subscription_payments where provider_reference = 'MP-CONC-DUP'")" == "1" ]] \
  || fail "même référence : plusieurs paiements"
[[ "$(psql_db -At -c "select status from public.covi_subscription_invoices where id = '$inv2'")" == "pending" ]] \
  || fail "même référence : la facture refusée n'est plus pending"
ok "même référence : un seul paiement enregistré, l'autre facture reste pending (23505)"

# 3. Quota 2, une boutique existante, deux créations simultanées ------------------------------
as_user "$o1" "select (public.create_my_shop('Conc A', null, 'Congo', 'XAF')).id" >/dev/null
run_pair "quota simultané" \
  "$o1" "select (public.create_my_shop('Conc B', null, 'Congo', 'XAF')).id::text" \
  "$o1" "select (public.create_my_shop('Conc C', null, 'Congo', 'XAF')).id::text"
grep -q '^res:' "$work/s1.out" || { cat "$work/s1.out" >&2; fail "quota : s1 aurait dû créer"; }
grep -q 'Shop quota reached' "$work/s2.out" || { cat "$work/s2.out" >&2; fail "quota : s2 aurait dû être refusée"; }
[[ "$(psql_db -At -c "select count(*) from public.shops where owner_id = '$o1'")" == "2" ]] \
  || fail "quota : plus de 2 boutiques"
ok "quota simultané : 2 boutiques au total, la 2e session reçoit 'Shop quota reached'"

# 4. Commerçant V1, deux créations simultanées ------------------------------------------------
run_pair "V1 simultané" \
  "$legacy" "select (public.create_my_shop('V1 un', null, 'Congo', 'XAF')).id::text" \
  "$legacy" "select (public.create_my_shop('V1 deux', null, 'Congo', 'XAF')).id::text"
[[ "$(psql_db -At -c "select count(*) from public.shops where owner_id = '$legacy'")" == "1" ]] \
  || fail "V1 : plus d'une boutique sans abonnement"
[[ "$(sed -n 's/^res://p' "$work/s1.out")" == "$(sed -n 's/^res://p' "$work/s2.out")" ]] \
  || { cat "$work/s1.out" "$work/s2.out" >&2; fail "V1 : les deux sessions devraient renvoyer la même boutique"; }
ok "V1 simultané : une seule boutique, la même renvoyée aux deux sessions (compatibilité V1)"
