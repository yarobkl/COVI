import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { randomUUID } from 'node:crypto'
import { createClient } from '@supabase/supabase-js'

const url = process.env.COVI_NATIVE_URL
const anonKey = process.env.COVI_NATIVE_ANON_KEY
const secretKey = process.env.COVI_NATIVE_SERVICE_KEY
if (process.env.COVI_NATIVE_CI !== 'true' ||
    !/^http:\/\/(127\.0\.0\.1|localhost):\d+$/.test(url ?? '') ||
    !anonKey || !secretKey ||
    process.env.PGHOST !== '127.0.0.1' ||
    process.env.PGPORT !== '54322' || process.env.PGDATABASE !== 'postgres')
  throw new Error('Native test must use disposable local Supabase only')

const { a, b, c } = JSON.parse(readFileSync('/tmp/covi-native-actors.json', 'utf8'))
const options = { auth: { persistSession: false, autoRefreshToken: false } }
const service = createClient(url, secretKey, options)
const anon = createClient(url, anonKey, options)
async function session(actor) {
  const client = createClient(url, anonKey, options)
  const response = await client.auth.signInWithPassword({
    email: actor.email, password: actor.password,
  })
  assert.ifError(response.error)
  assert.equal(response.data.user.id, actor.id)
  return client
}
const owner = await session(a)
const other = await session(b)
const cashier = await session(c)
async function rpc(client, name, args) {
  for (let i = 0; i < 6; i++) {
    const result = await client.rpc(name, args)
    if (result.error?.code === 'PGRST202' && i < 5) {
      await new Promise((resolve) => setTimeout(resolve, 700))
      continue
    }
    return result
  }
  throw new Error('PostgREST cache did not refresh')
}
async function denied(client, name, args, label) {
  const outcome = await rpc(client, name, args)
  assert.ok(outcome.error, label + ' must be refused')
}
const shop = '11111111-1111-4111-8111-111111111111'
const category = 'aaaaaaaa-0000-4000-8000-000000000002'
await denied(anon, 'get_checkout_public_link', { p_shop_id: shop }, 'Anonymous owner link')
await denied(other, 'get_checkout_public_link', { p_shop_id: shop }, 'Foreign owner link')
await denied(anon, 'get_checkout_public_catalog', { p_token: randomUUID() },
  'Direct guest catalogue RPC')
await denied(anon, 'submit_checkout_public_order', {
  p_token: randomUUID(), p_channel: 'qr', p_operation_id: randomUUID(), p_lines: [],
}, 'Direct guest creation RPC')
await denied(anon, 'consume_checkout_gateway_quota', {
  p_digest: 'a'.repeat(64), p_kind: 'order_source_minute',
}, 'Direct guest rate ceiling')
await denied(other, 'configure_checkout_public_link', {
  p_shop_id: shop, p_enabled: true,
}, 'Foreign owner cannot publish QR')
const activated = await rpc(owner, 'configure_checkout_public_link', {
  p_shop_id: shop, p_enabled: true,
})
assert.ifError(activated.error)
const token = activated.data.publicToken
assert.match(token, /^[0-9a-f-]{36}$/)
const catalog = await rpc(service, 'get_checkout_public_catalog', { p_token: token })
assert.ifError(catalog.error)
assert.deepEqual(catalog.data, {
  shopName: 'Boutique A',
  categories: [{ id: category, label: 'Robes' }],
})
const counted = await rpc(service, 'consume_checkout_gateway_quota', {
  p_digest: 'b'.repeat(64), p_kind: 'order_source_minute',
})
assert.ifError(counted.error)
assert.equal(counted.data, true)
const args = {
  p_token: token,
  p_channel: 'social',
  p_operation_id: randomUUID(),
  p_lines: [{ categoryId: category, quantity: 1, unitPriceXaf: 3500 }],
  p_fulfillment: 'pickup',
}
const created = await rpc(service, 'submit_checkout_public_order', args)
assert.ifError(created.error)
assert.equal(created.data.status, 'submitted')
assert.equal(created.data.amountXaf, 3500)
const retry = await rpc(service, 'submit_checkout_public_order', args)
assert.ifError(retry.error)
assert.equal(retry.data.orderId, created.data.orderId)
assert.equal(retry.data.shopId, shop)
const imagePath = shop + '/' + created.data.orderId + '/reference.jpg'
await denied(anon, 'attach_checkout_public_reference', {
  p_token: token,
  p_order_id: created.data.orderId,
  p_operation_id: args.p_operation_id,
  p_image_path: imagePath,
}, 'Anonymous photo attachment')
await denied(other, 'attach_checkout_public_reference', {
  p_token: token,
  p_order_id: created.data.orderId,
  p_operation_id: args.p_operation_id,
  p_image_path: imagePath,
}, 'Foreign shop image attachment')
const referenceImage = Buffer.from([255, 216, 255, 224, 0, 1, 2, 3, 255, 217])
const uploaded = await service.storage.from('covi-order-references')
  .upload(imagePath, referenceImage, { contentType: 'image/jpeg', upsert: false })
assert.ifError(uploaded.error)
const attached = await rpc(service, 'attach_checkout_public_reference', {
  p_token: token,
  p_order_id: created.data.orderId,
  p_operation_id: args.p_operation_id,
  p_image_path: imagePath,
})
assert.ifError(attached.error)
assert.equal(attached.data, true)
const ownerPicture = await owner.storage.from('covi-order-references').createSignedUrl(imagePath, 60)
assert.ifError(ownerPicture.error)
assert.ok(ownerPicture.data?.signedUrl?.includes('reference.jpg'))
const outsiderPicture = await other.storage.from('covi-order-references').createSignedUrl(imagePath, 60)
assert.ok(outsiderPicture.error, 'Other shop must not sign the customer picture')
const guestPicture = await anon.storage.from('covi-order-references').createSignedUrl(imagePath, 60)
assert.ok(guestPicture.error, 'Anonymous customer cannot access private order image')
const queue = await rpc(owner, 'get_checkout_pending_orders', { p_shop_id: shop })
assert.ifError(queue.error)
assert.ok(queue.data.some((x) => x.orderId === created.data.orderId && x.referenceImagePath === imagePath))
await denied(other, 'get_checkout_pending_orders', { p_shop_id: shop },
  'Foreign owner cannot read private orders')

await denied(cashier, 'get_checkout_pending_orders', { p_shop_id: shop },
  'Uninvited cashier has no checkout access')
const invite = await rpc(owner, 'create_checkout_cashier_invite', {
  p_shop_id: shop, p_first_name: 'Aminata',
})
assert.ifError(invite.error)
assert.match(invite.data.inviteCode, /^[0-9a-f-]{36}$/)
await denied(other, 'set_checkout_cashier_active', {
  p_shop_id: shop, p_cashier_user_id: c.id, p_active: false,
}, 'Other boutique cannot manage staff')
const joined = await rpc(cashier, 'redeem_checkout_cashier_invite', {
  p_invite_code: invite.data.inviteCode,
})
assert.ifError(joined.error)
assert.equal(joined.data.shopId, shop)
await denied(other, 'redeem_checkout_cashier_invite', {
  p_invite_code: invite.data.inviteCode,
}, 'Cashier invitation is one-use')
const enrolled = await rpc(cashier, 'set_checkout_cashier_pin', {
  p_shop_id: shop, p_new_pin: '837294',
})
assert.ifError(enrolled.error)
assert.equal(enrolled.data, true)
const staffShops = await rpc(cashier, 'get_my_checkout_cashier_shops', {})
assert.ifError(staffShops.error)
assert.equal(staffShops.data.length, 1)
assert.equal(staffShops.data[0].pinConfigured, true)
const cashierQueue = await rpc(cashier, 'get_checkout_pending_orders', { p_shop_id: shop })
assert.ifError(cashierQueue.error)
assert.ok(cashierQueue.data.length >= 1)
await denied(cashier, 'configure_checkout_public_link', {
  p_shop_id: shop, p_enabled: false,
}, 'Employee cannot change the public shop QR link')
await denied(cashier, 'set_checkout_cashier_active', {
  p_shop_id: shop, p_cashier_user_id: c.id, p_active: false,
}, 'Employee cannot edit own role')
const badPin = await rpc(cashier,'confirm_manual_checkout_payment', {
  p_shop_id:shop, p_order_id:created.data.orderId,p_operation_id:randomUUID(),
  p_cashier_first_name:'Aminata',p_method:'cash',p_pin:'111111',
})
assert.ifError(badPin.error)
assert.equal(badPin.data.pinRejected,true)
const disabled = await rpc(owner,'set_checkout_cashier_active',{
  p_shop_id:shop,p_cashier_user_id:c.id,p_active:false,
})
assert.ifError(disabled.error)
await denied(cashier,'get_checkout_pending_orders',{p_shop_id:shop},
  'Revoked staff cannot read checkout orders')

const stock = await service.from('stock_categories').select('quantity_on_hand').eq('id', category).single()
assert.ifError(stock.error)
assert.equal(stock.data.quantity_on_hand, 3, 'Orders never decrement stock')
const sales = await service.from('sales').select('id', { count: 'exact', head: true })
assert.ifError(sales.error)
assert.equal(sales.count, 0, 'No sale/payments generated by a visitor')
console.log('PASS: Native Supabase Auth login, PostgREST role denials, owner RLS, private inbox, service-only creation, idempotency and unchanged stock')
