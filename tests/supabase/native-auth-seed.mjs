import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { writeFileSync } from 'node:fs'
import { createClient } from '@supabase/supabase-js'

const url = process.env.COVI_NATIVE_URL
const key = process.env.COVI_NATIVE_SERVICE_KEY
if (process.env.COVI_NATIVE_CI !== 'true' ||
    !/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(url ?? '') ||
    !key || process.env.PGHOST !== '127.0.0.1' ||
    process.env.PGPORT !== '54322' || process.env.PGDATABASE !== 'postgres')
  throw new Error('Refusing to seed outside disposable local Supabase')

const admin = createClient(url, key, { auth: { persistSession: false } })
async function owner() {
  const email = 'covi-local-' + randomUUID() + '@example.test'
  const password = 'Covi-Test-' + randomUUID() + '-9A'
  const { data, error } = await admin.auth.admin.createUser({
    email, password, email_confirm: true,
  })
  assert.ifError(error)
  assert.match(data.user.id, /^[0-9a-f-]{36}$/)
  return { id: data.user.id, email, password }
}
const a = await owner()
const b = await owner()
writeFileSync('/tmp/covi-native-actors.json', JSON.stringify({ a, b }), { mode: 0o600 })

const sql = [
  "insert into public.shops (id,owner_id,name) values",
  "('11111111-1111-4111-8111-111111111111','" + a.id + "','Boutique A'),",
  "('22222222-2222-4222-8222-222222222222','" + b.id + "','Boutique B');",
  "insert into public.stock_categories",
  "(id,shop_id,category_key,display_name,quantity_on_hand,quantity_reserved,is_test)",
  "values ('aaaaaaaa-0000-4000-8000-000000000002',",
  "'11111111-1111-4111-8111-111111111111','robes','Robes',3,0,false);",
].join(' ')
writeFileSync('/tmp/covi-native-seed.sql', sql + '\n', { mode: 0o600 })
console.log('PASS: two isolated Supabase Auth users created; no external account accessed')
