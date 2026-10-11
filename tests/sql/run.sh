#!/usr/bin/env bash
# Banc de test SQL de COVI.
#
# Sur une base PostgreSQL vierge : crée les stubs Supabase (tests/sql/bootstrap.sql), applique
# toutes les migrations de supabase/migrations dans l'ordre, puis exécute chaque test
# tests/sql/*.sql (hors bootstrap.sql) et chaque script tests/sql/*.sh (hors run.sh : tests à
# plusieurs sessions psql, ex. concurrence). Le moindre échec rend un code non nul.
#
# Usage :
#   tests/sql/run.sh                 # serveur désigné par PGHOST/PGPORT/PGUSER/PGPASSWORD
#   tests/sql/run.sh --tmp-cluster   # crée un cluster jetable (initdb) et le détruit à la fin
#
# Variables :
#   COVI_TEST_DB  nom de la base de test, détruite puis recréée (défaut : covi_test)
#   PG_BIN        dossier des binaires PostgreSQL pour --tmp-cluster
#                 (défaut : /usr/lib/postgresql/16/bin)
#
# Ne jamais pointer ce script vers la base de production : il supprime la base COVI_TEST_DB.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
db="${COVI_TEST_DB:-covi_test}"
export PGTZ=UTC

if [[ "${1:-}" == "--tmp-cluster" ]]; then
  pg_bin="${PG_BIN:-/usr/lib/postgresql/16/bin}"
  cluster="$(mktemp -d "${TMPDIR:-/tmp}/covi-pg.XXXXXX")"
  as_pg=()
  if [[ "$(id -u)" == "0" ]]; then
    # initdb refuse de tourner en root : le cluster appartient à l'utilisateur postgres.
    chown postgres "$cluster"
    as_pg=(runuser -u postgres --)
  fi
  cleanup() {
    "${as_pg[@]}" "$pg_bin/pg_ctl" -D "$cluster/data" -m immediate stop >/dev/null 2>&1 || true
    rm -rf "$cluster"
  }
  trap cleanup EXIT
  "${as_pg[@]}" "$pg_bin/initdb" -D "$cluster/data" -U postgres -A trust --no-sync >/dev/null
  "${as_pg[@]}" "$pg_bin/pg_ctl" -D "$cluster/data" -l "$cluster/server.log" -w \
    -o "-c listen_addresses='' -c unix_socket_directories='$cluster' -c fsync=off" start >/dev/null
  export PGHOST="$cluster" PGPORT=5432 PGUSER=postgres
  unset PGPASSWORD
fi

psql_db() { psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }

echo "== Base de test $db sur ${PGHOST:-localhost}:${PGPORT:-5432}"
psql -X -q -v ON_ERROR_STOP=1 -d postgres -c "set client_min_messages = warning" \
  -c "drop database if exists \"$db\"" \
  -c "create database \"$db\""

echo "== Stubs Supabase"
psql_db -f "$here/bootstrap.sql" >/dev/null

echo "== Migrations"
for migration in "$root"/supabase/migrations/*.sql; do
  echo "   $(basename "$migration")"
  PGOPTIONS="-c client_min_messages=warning" psql_db -1 -f "$migration" >/dev/null
done

echo "== Tests"
failed=0
for test in "$here"/*.sql; do
  name="$(basename "$test")"
  [[ "$name" == "bootstrap.sql" ]] && continue
  echo "-- $name"
  if psql_db -At -f "$test"; then
    echo "   PASS $name"
  else
    echo "   FAIL $name"
    failed=1
  fi
done

# Tests à plusieurs sessions (concurrence) : scripts tests/sql/*.sh hors run.sh.
export COVI_TEST_DB="$db"
for test in "$here"/*.sh; do
  name="$(basename "$test")"
  [[ "$name" == "run.sh" ]] && continue
  echo "-- $name"
  if bash "$test"; then
    echo "   PASS $name"
  else
    echo "   FAIL $name"
    failed=1
  fi
done

if [[ "$failed" != "0" ]]; then
  echo "== ÉCHEC : au moins un test SQL a échoué"
  exit 1
fi
echo "== Tous les tests SQL passent"
