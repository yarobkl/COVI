#!/usr/bin/env bash
# Ephemeral PostgreSQL only. PGHOST, PGUSER, PGDATABASE and PGPASSWORD come
# from the disposable GitHub Actions Postgres service; never from Supabase.
set -euo pipefail

if [[ "$PGDATABASE" != "covi_ci" ]]; then
  echo "Refusing to run: PGDATABASE must be covi_ci" >&2
  exit 2
fi

if [[ "$PGHOST" != "127.0.0.1" && "$PGHOST" != "localhost" ]]; then
  echo "Refusing to run: PostgreSQL host must be localhost" >&2
  exit 2
fi

if [[ -n "${SUPABASE_URL-}" || -n "${DATABASE_URL-}" ]]; then
  echo "Refusing to run with Supabase or DATABASE_URL environment" >&2
  exit 2
fi

run() {
  psql -X -v ON_ERROR_STOP=1 --no-password --file "$1"
}

echo "Preparing isolated PostgreSQL fixture..."
run tests/postgres/fixture.sql
echo "Loading only explicitly named review SQL from the non-migration directory..."
run supabase/sql-drafts/draft_category_stock_schema.sql
run supabase/sql-drafts/draft_checkout_manual_payment_schema.sql
run supabase/sql-drafts/draft_post_arrival_category_stock.sql
run supabase/sql-drafts/draft_create_approve_manual_checkout_order.sql
run supabase/sql-drafts/draft_confirm_manual_checkout_payment.sql
echo "Running real PostgreSQL manual checkout smoke scenarios..."
run tests/postgres/manual-checkout-smoke.sql
echo "PASS: SQL smoke tests completed in disposable covi_ci database."
