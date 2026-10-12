import { existsSync, readFileSync, readdirSync } from 'node:fs'
import assert from 'node:assert/strict'
import { join } from 'node:path'

const draftsDir = 'supabase/sql-drafts'
const migrationsDir = 'supabase/migrations'
const expected = [
  'draft_category_stock_schema.sql',
  'draft_checkout_manual_payment_schema.sql',
  'draft_create_approve_manual_checkout_order.sql',
  'draft_confirm_manual_checkout_payment.sql',
  'draft_post_arrival_category_stock.sql',
]

assert.ok(existsSync(draftsDir), 'SQL draft directory must exist')
for (const name of expected) {
  const path = join(draftsDir, name)
  assert.ok(existsSync(path), 'Missing draft: ' + name)
  const sql = readFileSync(path, 'utf8')
  assert.match(sql, /DRAFT|draft|REVIEW ONLY|NOT APPLIED|DO NOT/i,
    'SQL must be conspicuously identified as unapproved: ' + name)
  assert.match(sql, /begin;/i, 'Use explicit transaction boundary: ' + name)
  assert.match(sql, /commit;/i, 'Use explicit transaction boundary: ' + name)
  assert.ok(!existsSync(join(migrationsDir, name)),
    'Unapproved SQL must never be inside automatic migrations: ' + name)
}

const executableFiles = existsSync(migrationsDir) ? readdirSync(migrationsDir) : []
assert.deepEqual(
  executableFiles.filter((name) => /^draft_.*\.sql$/i.test(name)),
  [],
  'Never place experimental SQL in executable migration directory',
)

for (const name of [
  'draft_create_approve_manual_checkout_order.sql',
  'draft_confirm_manual_checkout_payment.sql',
  'draft_post_arrival_category_stock.sql',
]) {
  const sql = readFileSync(join(draftsDir, name), 'utf8')
  assert.match(sql, /security definer/i, 'Server-controlled write function required: ' + name)
  assert.match(sql, /auth\.uid\(\)/i, 'Explicit caller identity required: ' + name)
  assert.match(sql, /revoke all on function/i, 'Function must revoke PUBLIC/anon: ' + name)
  assert.match(sql, /grant execute on function/i,
    'Function must explicitly grant appropriate execute role: ' + name)
}

const paymentSql = readFileSync(
  join(draftsDir, 'draft_confirm_manual_checkout_payment.sql'), 'utf8',
)
assert.match(paymentSql, /v_order\.status <> 'approved'/,
  'Only approved orders can be paid')
assert.match(paymentSql, /for update/i, 'Atomic payment path must lock rows')
assert.match(paymentSql, /v_existing\.operation_id = p_operation_id/,
  'Duplicate payment should return the original receipt')
assert.match(paymentSql, /insert into public\.manual_payment_confirmations/,
  'Cashier attestation must be recorded')
assert.match(paymentSql, /insert into public\.stock_movements/,
  'Stock movement must be journaled')
assert.match(paymentSql, /v_actor/, 'The true authenticated caller must be recorded')

console.log('PASS: Five SQL drafts isolated; explicit auth, locks, duplicate guards and receipts present.')
console.log('NOTE: Static tests do NOT establish SQL execution, RLS safety or concurrency correctness.')
