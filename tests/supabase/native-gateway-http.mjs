import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'
import { createPublicCheckoutGateway } from '../../supabase/functions/public-checkout/gateway.mjs'

const localUrl = process.env.COVI_NATIVE_URL
const serverKey = process.env.COVI_NATIVE_SERVICE_KEY
if (process.env.COVI_NATIVE_CI !== 'true' ||
    !/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(localUrl ?? '') ||
    !serverKey || process.env.PGHOST !== '127.0.0.1' ||
    process.env.PGDATABASE !== 'postgres' || process.env.PGPORT !== '54322')
  throw new Error('Refusing to run gateway outside disposable local Supabase')

const client = createClient(localUrl, serverKey, { auth: { persistSession: false } })
const link = await client.from('checkout_public_links')
  .select('public_token').eq('shop_id', '11111111-1111-4111-8111-111111111111').single()
assert.ifError(link.error)
const token = link.data.public_token
const origin = 'https://covi-native.example'
const backend = 'https://isolated-native-backend.example'
const env = {
  COVI_GATEWAY_ENABLED: 'true',
  COVI_PUBLIC_ORIGIN: origin,
  SUPABASE_URL: backend,
  COVI_SUPABASE_SECRET_KEY: serverKey,
  COVI_GATEWAY_PEPPER: 'ephemeral-only-pepper-with-minimum-32-characters',
  COVI_TURNSTILE_SECRET: 'ephemeral-only-turnstile-test-secret',
}
let verifiedChallenges = 0
async function localTransport(url, init) {
  if (String(url).startsWith('https://challenges.cloudflare.com/')) {
    verifiedChallenges++
    return Response.json({
      success: true, hostname: 'covi-native.example', action: 'covi_checkout',
    })
  }
  const target = new URL(String(url))
  assert.equal(target.origin, backend)
  return fetch(localUrl + target.pathname, init)
}
const gateway = createPublicCheckoutGateway(env, localTransport)
const catalog = await gateway(new Request(
  backend + '/functions/v1/public-checkout?token=' + token,
  { headers: { Origin: origin } },
))
assert.equal(catalog.status, 200, await catalog.clone().text())
const info = await catalog.json()
assert.deepEqual(info.categories, [{
  id: 'aaaaaaaa-0000-4000-8000-000000000002', label: 'Robes',
}])
const originalOperation = randomUUID()
const payload = {
  token, channel: 'qr', operationId: originalOperation, fulfillment: 'pickup',
  lines: [{
    categoryId: 'aaaaaaaa-0000-4000-8000-000000000002',
    quantity: 1, unitPriceXaf: 4200,
  }],
  challenge: 'mocked-human-challenge-for-local-integration',
}
function guest(body, address = origin) {
  return new Request(backend + '/functions/v1/public-checkout', {
    method: 'POST',
    headers: { Origin: address, 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
}
const foreign = await gateway(guest(payload, 'https://attacker.example'))
assert.equal(foreign.status, 403)
const first = await gateway(guest(payload))
assert.equal(first.status, 200, await first.clone().text())
const submitted = await first.json()
assert.equal(submitted.status, 'submitted')
assert.equal(submitted.amountXaf, 4200)
const repeated = await gateway(guest(payload))
assert.equal(repeated.status, 200, await repeated.clone().text())
assert.equal((await repeated.json()).orderId, submitted.orderId)
assert.equal(verifiedChallenges, 2, 'Every attempt must pass server-side verification')
const stock = await client.from('stock_categories').select('quantity_on_hand')
  .eq('id', 'aaaaaaaa-0000-4000-8000-000000000002').single()
assert.ifError(stock.error)
assert.equal(stock.data.quantity_on_hand, 3)
const payments = await client.from('manual_payment_confirmations')
  .select('order_id', { head: true, count: 'exact' })
assert.ifError(payments.error)
assert.equal(payments.count, 0)
console.log('PASS: Guest HTTP gateway -> real local PostgREST -> private request, safe retry, no payment and no stock movement (captcha mocked)')
