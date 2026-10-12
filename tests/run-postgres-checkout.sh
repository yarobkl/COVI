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

echo "Preparing two approved orders for the final garment and one duplicate-payment order..."
run tests/postgres/concurrency-setup.sql

# Separate psql processes issue actual overlapping SQL transactions.
# Expected outcomes: two independent orders -> exactly one succeeds;
# same order + same idempotency key -> both succeed with ONE persisted sale.
pay_parallel() {
  local operation_a="$1"
  local operation_b="$2"
  local payment_a="$3"
  local payment_b="$4"
  local expected="$5"
  local log_a
  local log_b
  local pid_a
  local pid_b
  local status_a
  local status_b
  log_a="$(mktemp)"
  log_b="$(mktemp)"

  psql -X -v ON_ERROR_STOP=1 --no-password \
    -v "created_op=$operation_a" -v "payment_op=$payment_a" \
    --file tests/postgres/concurrency-payment.sql > "$log_a" 2>&1 &
  pid_a=$!
  sleep 0.2
  psql -X -v ON_ERROR_STOP=1 --no-password \
    -v "created_op=$operation_b" -v "payment_op=$payment_b" \
    --file tests/postgres/concurrency-payment.sql > "$log_b" 2>&1 &
  pid_b=$!

  status_a=0
  status_b=0
  wait "$pid_a" || status_a=$?
  wait "$pid_b" || status_b=$?

  if [[ "$expected" == "exclusive" ]]; then
    if ! { [[ "$status_a" -eq 0 && "$status_b" -ne 0 ]] ||
           [[ "$status_a" -ne 0 && "$status_b" -eq 0 ]]; }; then
      echo "FAIL: expected one successful last-garment sale and one stock rejection" >&2
      cat "$log_a" "$log_b" >&2
      rm -f "$log_a" "$log_b"
      return 1
    fi
  else
    if [[ "$status_a" -ne 0 || "$status_b" -ne 0 ]]; then
      echo "FAIL: expected two identical requests to return the same saved sale" >&2
      cat "$log_a" "$log_b" >&2
      rm -f "$log_a" "$log_b"
      return 1
    fi
    # Both responses must contain the receipt number from the SAME DB row;
    # row identity and stock are also asserted by the SQL verification below.
  fi
  rm -f "$log_a" "$log_b"
}

echo "Running two truly concurrent last-garment confirmations..."
pay_parallel \
  "33330000-0000-4000-8000-000000000001" \
  "33330000-0000-4000-8000-000000000002" \
  "44440000-0000-4000-8000-000000000001" \
  "44440000-0000-4000-8000-000000000002" \
  "exclusive"
run tests/postgres/concurrency-last-item-assert.sql

echo "Running concurrent identical retries against one order..."
pay_parallel \
  "33330000-0000-4000-8000-000000000003" \
  "33330000-0000-4000-8000-000000000003" \
  "44440000-0000-4000-8000-000000000003" \
  "44440000-0000-4000-8000-000000000003" \
  "idempotent"
run tests/postgres/concurrency-same-order-assert.sql
echo "PASS: Disposable PostgreSQL integration AND concurrency checks succeeded."

echo "Running security, rollback and TEST/real stock isolation scenarios..."
run tests/postgres/checkout-security-assert.sql
echo "PASS: Security and rollback scenarios completed."
