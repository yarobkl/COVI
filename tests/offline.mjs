import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'

// Test the production offline module with browser storage and RPC outcomes controlled.
const values = new Map()
globalThis.localStorage = {
  getItem: (k) => values.get(k) ?? null,
  setItem: (k, v) => values.set(k, String(v)),
  removeItem: (k) => values.delete(k),
}
globalThis.window = new EventTarget()
Object.defineProperty(globalThis, 'navigator', { value: { onLine: false }, configurable: true })
// Controlled clock and timers so the sync backoff can be observed without waiting.
let now = 1_000_000
Date.now = () => now
const timers = new Map()
let timerSeq = 0
globalThis.setTimeout = (fn, ms) => {
  const id = ++timerSeq
  timers.set(id, { fn, at: now + ms })
  return id
}
globalThis.clearTimeout = (id) => {
  timers.delete(id)
}
const fireTimers = async () => {
  const due = [...timers].filter(([, t]) => t.at <= now)
  for (const [id, t] of due) {
    timers.delete(id)
    t.fn()
  }
  await new Promise((r) => setImmediate(r))
}
let syncEvents = 0
window.addEventListener('covi-sync', () => syncEvents++)
const source = await readFile(new URL('../src/lib/offline.ts', import.meta.url), 'utf8')
const compiled = stripTypeScriptTypes(source)
// Whitespace-agnostic so that reformatting offline.ts cannot silently skip the mock.
const moduleSource = compiled.replaceAll(
  /await\s+import\(\s*'\.\/covi'\s*\)/g,
  'globalThis.testBackend',
)
assert.ok(!moduleSource.includes("'./covi'"), 'every backend import of offline.ts is mocked')
const offlineUrl = 'data:text/javascript;base64,' + Buffer.from(moduleSource).toString('base64')
const offline = await import(offlineUrl)
const input = {
  shopId: 'test-shop',
  productId: 'test-product',
  quantity: 1,
  soldUnitPrice: 15000,
  paymentLabel: 'Espèces',
}
const seed = () =>
  offline.cacheStock(input.shopId, [{ id: input.productId, quantity_on_hand: 1, status: 'active' }])
seed()
// Without a signed-in account an offline sale cannot be attributed: refuse it instead of queueing an orphan.
await assert.rejects(offline.resilientSale(input), /Session introuvable/)
assert.equal(values.get('covi:pending-sales:v1'), undefined)
offline.setSyncUser('user-a')
assert.deepEqual(await offline.resilientSale(input), { offline: true })
assert.equal(offline.pendingSales()[0].userId, 'user-a')
assert.equal(offline.pendingCount(), 1)
assert.equal(offline.cachedStock(input.shopId)[0].quantity_on_hand, 0)
assert.equal(offline.cachedStock(input.shopId)[0].status, 'sold')
await assert.rejects(offline.resilientSale(input), /insuffisant/)
const operation = offline.pendingSales()[0].id
navigator.onLine = true
let failures = 0
globalThis.testBackend = {
  recordSale: async () => {
    failures++
    throw new Error('Failed to fetch')
  },
}
// A SyncStatus-like listener re-syncs on every covi-sync event: a network failure must not loop.
const resync = () => {
  if (navigator.onLine && offline.pendingCount() > 0) void offline.syncPendingSales()
}
window.addEventListener('covi-sync', resync)
syncEvents = 0
await offline.syncPendingSales()
await new Promise((r) => setImmediate(r))
assert.equal(failures, 1)
assert.equal(syncEvents, 0, 'a failed sync changes nothing and must not emit covi-sync')
assert.equal(offline.pendingCount(), 1)
assert.equal(offline.pendingSales()[0].id, operation)
assert.equal(offline.pendingSales()[0].attempts, 1)
assert.equal(offline.nextSyncRetryAt(), now + 5000)
assert.equal(timers.size, 1)
await offline.syncPendingSales()
now += 4999
await offline.syncPendingSales()
await fireTimers()
assert.equal(failures, 1, 'no second call before the backoff deadline')
const delays = []
for (let i = 0; i < 8; i++) {
  now = offline.nextSyncRetryAt()
  await fireTimers()
  delays.push(offline.nextSyncRetryAt() - now)
  assert.equal(timers.size, 1, 'a single retry timer')
}
assert.deepEqual(delays, [10000, 20000, 40000, 80000, 160000, 300000, 300000, 300000])
assert.equal(failures, 9)
assert.equal(offline.pendingSales()[0].attempts, 9)
window.removeEventListener('covi-sync', resync)
let calls = 0
globalThis.testBackend = {
  recordSale: async (...args) => {
    calls++
    assert.equal(args[5], operation)
  },
}
await Promise.all([offline.syncPendingSales(), offline.syncPendingSales()])
assert.equal(calls, 0, 'still waiting for the retry deadline')
now = offline.nextSyncRetryAt()
await Promise.all([offline.syncPendingSales(), offline.syncPendingSales()])
assert.equal(calls, 1)
assert.equal(offline.nextSyncRetryAt(), 0)
assert.equal(timers.size, 0, 'success clears the retry timer')
assert.equal(offline.pendingCount(), 0)
assert.equal(offline.cachedStock(input.shopId)[0].quantity_on_hand, 0)
navigator.onLine = false
seed()
await offline.resilientSale(input)
navigator.onLine = true
globalThis.testBackend = {
  recordSale: async () => {
    throw new Error('Insufficient stock')
  },
}
const rejected = await offline.syncPendingSales()
assert.equal(rejected.rejected, 1)
assert.equal(offline.pendingCount(), 0)
assert.equal(offline.cachedStock(input.shopId)[0].quantity_on_hand, 1)
assert.equal(offline.cachedStock(input.shopId)[0].status, 'active')
assert.equal(offline.rejectedSaleCount(), 1)
// A rejected sale is never dropped: it is kept with its reason, and dismissing the notice keeps the record.
const kept = JSON.parse(values.get('covi:rejected-sales:v2'))
assert.equal(kept.length, 1)
assert.equal(kept[0].reason, 'Insufficient stock')
assert.equal(kept[0].userId, 'user-a')
assert.equal(kept[0].productId, input.productId)
offline.clearRejectedSaleCount()
assert.equal(offline.rejectedSaleCount(), 0)
assert.equal(offline.rejectedSales().length, 1)
assert.equal(offline.rejectedSales()[0].dismissed, true)

// Per-account queue: user A's offline sale is neither shown to nor sent by user B, and survives the switch.
navigator.onLine = false
seed()
await offline.resilientSale(input)
const saleOfA = offline.pendingSales()[0].id
offline.setSyncUser(null)
assert.equal(offline.pendingCount(), 0)
offline.setSyncUser('user-b')
assert.equal(offline.pendingCount(), 0)
assert.equal(offline.rejectedSales().length, 0)
navigator.onLine = true
const sent = []
globalThis.testBackend = {
  recordSale: async (...args) => {
    sent.push(args[5])
  },
}
assert.deepEqual(await offline.syncPendingSales(), { synced: 0, pending: 0, rejected: 0 })
assert.deepEqual(sent, [])
assert.equal(JSON.parse(values.get('covi:pending-sales:v1')).length, 1, 'user A sale still stored')
offline.setSyncUser('user-a')
assert.equal(offline.pendingCount(), 1)
await offline.syncPendingSales()
assert.deepEqual(sent, [saleOfA])
assert.equal(offline.pendingCount(), 0)

// Sales queued before userId existed are synced by the signed-in account; a legacy rejection counter is still shown.
values.set(
  'covi:pending-sales:v1',
  JSON.stringify([
    {
      id: 'legacy-op',
      shopId: input.shopId,
      productId: input.productId,
      quantity: 1,
      soldUnitPrice: 1,
      paymentLabel: 'Espèces',
      createdAt: '2026-01-01T00:00:00.000Z',
      attempts: 0,
    },
  ]),
)
values.set('covi:rejected-sales:v1', '2')
assert.equal(offline.pendingCount(), 1)
assert.equal(offline.rejectedSaleCount(), 2)
await offline.syncPendingSales()
assert.deepEqual(sent, [saleOfA, 'legacy-op'])
offline.clearRejectedSaleCount()
assert.equal(offline.rejectedSaleCount(), 0)

// A sale queued while a sync is awaiting the server must not be overwritten by the sync.
navigator.onLine = false
seed()
await offline.resilientSale(input)
navigator.onLine = true
let release
globalThis.testBackend = {
  recordSale: () =>
    new Promise((r) => {
      release = r
    }),
}
const running = offline.syncPendingSales()
await new Promise((r) => setImmediate(r))
offline.queueSale({ ...input, userId: 'user-a' }, 'queued-during-sync')
release()
await running
assert.deepEqual(
  offline.pendingSales().map((x) => x.id),
  ['queued-during-sync'],
)

// listProducts (covi.ts) against a mocked Supabase: the active stock, test products included, feeds the offline cache.
let productRows = [],
  productsFail = null,
  authListener
const productFilters = []
const rpcCalls = []
globalThis.mockSupabase = {
  rpc: async (fn, args) => {
    rpcCalls.push([fn, args])
    return { data: 'sale-id', error: null }
  },
  auth: {
    onAuthStateChange: (cb) => {
      authListener = cb
      return { data: { subscription: { unsubscribe() {} } } }
    },
  },
  storage: {
    from: () => ({
      createSignedUrl: async (path) => ({ data: { signedUrl: 'signed:' + path }, error: null }),
    }),
  },
  from: () => {
    const filters = []
    productFilters.push(filters)
    const q = {
      select: () => q,
      order: () => q,
      eq: (col, v) => {
        filters.push([col, v])
        return q
      },
      then: (ok, ko) =>
        (productsFail
          ? Promise.reject(productsFail)
          : Promise.resolve({
              data: productRows.filter((row) =>
                filters.every(([col, v]) => col === 'shop_id' || row[col] === v),
              ),
              error: null,
            })
        ).then(ok, ko),
    }
    return q
  },
}
// format.ts (payment codes) is a pure module without imports: load it as is.
const formatSource = stripTypeScriptTypes(
  await readFile(new URL('../src/lib/format.ts', import.meta.url), 'utf8'),
)
assert.ok(!/^\s*import\s/m.test(formatSource), 'format.ts must stay free of imports')
const formatUrl = 'data:text/javascript;base64,' + Buffer.from(formatSource).toString('base64')
const coviSource = stripTypeScriptTypes(
  await readFile(new URL('../src/lib/covi.ts', import.meta.url), 'utf8'),
)
  .replace(
    /import\s*\{\s*supabase\s*\}\s*from\s*'\.\/supabase'/,
    'const supabase=globalThis.mockSupabase',
  )
  .replace(/from\s*'\.\/offline'/, `from'${offlineUrl}'`)
  .replace(/from\s*'\.\/format'/, `from'${formatUrl}'`)
assert.ok(coviSource.includes(offlineUrl), 'covi.ts must share the tested offline module')
assert.ok(!/from\s*'\.\//.test(coviSource), 'covi.ts has no unmocked relative import')
const covi = await import(
  'data:text/javascript;base64,' + Buffer.from(coviSource).toString('base64')
)
// recordSale stores the payment code matching the checkout label (unknown labels become 'other').
assert.equal(await covi.recordSale('s', 'p', 2, 1500, 'Mobile Money', 'op-1'), 'sale-id')
await covi.recordSale('s', 'p', 1, 1500, 'Bon d’achat', 'op-2')
assert.deepEqual(rpcCalls, [
  [
    'record_sale',
    {
      p_shop_id: 's',
      p_product_id: 'p',
      p_quantity: 2,
      p_sold_unit_price: 1500,
      p_payment_method: 'mobile_money',
      p_client_operation_id: 'op-1',
    },
  ],
  [
    'record_sale',
    {
      p_shop_id: 's',
      p_product_id: 'p',
      p_quantity: 1,
      p_sold_unit_price: 1500,
      p_payment_method: 'other',
      p_client_operation_id: 'op-2',
    },
  ],
])
// The auth listener binds the queue to the signed-in account (deferred out of the auth callback).
authListener('SIGNED_OUT', null)
await fireTimers()
assert.equal(offline.pendingCount(), 0)
authListener('SIGNED_IN', { user: { id: 'user-a' } })
await fireTimers()
assert.equal(offline.pendingCount(), 1)
const shop = 'shop-cache'
productRows = [
  {
    id: 'real',
    shop_id: shop,
    name: 'Robe',
    status: 'active',
    is_test: false,
    quantity_on_hand: 2,
    image_path: null,
  },
  {
    id: 'demo',
    shop_id: shop,
    name: 'Robe test',
    status: 'active',
    is_test: true,
    quantity_on_hand: 1,
    image_path: 'p/demo.jpg',
  },
  {
    id: 'gone',
    shop_id: shop,
    name: 'Vendue',
    status: 'sold',
    is_test: false,
    quantity_on_hand: 0,
    image_path: null,
  },
]
navigator.onLine = true
assert.deepEqual(
  (await covi.listProducts(shop, false, true)).map((x) => x.id),
  ['real', 'demo'],
)
assert.deepEqual(
  offline.cachedStock(shop).map((x) => x.id),
  ['real', 'demo'],
  'test products are cached',
)
assert.equal(offline.cachedStock(shop)[1].image_url, 'signed:p/demo.jpg')
assert.deepEqual(
  (await covi.listProducts(shop)).map((x) => x.id),
  ['real'],
  'includeTest=false hides test products',
)
assert.deepEqual(
  offline.cachedStock(shop).map((x) => x.id),
  ['real', 'demo'],
  'includeTest=false still caches the full active stock',
)
assert.ok(!productFilters.at(-1).some(([col]) => col === 'is_test'))
assert.deepEqual(
  (await covi.listProducts(shop, true, false)).map((x) => x.id),
  ['real', 'gone'],
)
assert.deepEqual(productFilters.at(-1), [
  ['shop_id', shop],
  ['is_test', false],
])
assert.deepEqual(
  offline.cachedStock(shop).map((x) => x.id),
  ['real', 'demo'],
  'the sold history does not overwrite the cache',
)
// Offline fallback serves the cache (test products only when requested), and the cached test product can be sold offline.
productsFail = new Error('Failed to fetch')
navigator.onLine = false
assert.deepEqual(
  (await covi.listProducts(shop, false, true)).map((x) => x.id),
  ['real', 'demo'],
)
assert.deepEqual(
  (await covi.listProducts(shop)).map((x) => x.id),
  ['real'],
)
await assert.rejects(covi.listProducts(shop, true, true), /Failed to fetch/)
assert.deepEqual(await offline.resilientSale({ ...input, shopId: shop, productId: 'demo' }), {
  offline: true,
})
assert.equal(offline.cachedStock(shop).find((x) => x.id === 'demo').status, 'sold')
assert.deepEqual(
  (await covi.listProducts(shop, false, true)).map((x) => x.id),
  ['real'],
  'a product sold out offline leaves the offline list',
)
await assert.rejects(
  offline.resilientSale({ ...input, shopId: shop, productId: 'demo' }),
  /insuffisant/,
)
// Refreshing from the server keeps queued offline sales reserved in the cache (the server has not seen them yet).
productsFail = null
navigator.onLine = true
assert.deepEqual(
  (await covi.listProducts(shop, false, true)).map((x) => x.id),
  ['real', 'demo'],
  'the server still lists the piece',
)
assert.equal(offline.cachedStock(shop).find((x) => x.id === 'demo').status, 'sold')
assert.equal(offline.cachedStock(shop).find((x) => x.id === 'demo').quantity_on_hand, 0)
assert.equal(offline.cachedStock(shop).find((x) => x.id === 'real').quantity_on_hand, 2)
navigator.onLine = false
await assert.rejects(
  offline.resilientSale({ ...input, shopId: shop, productId: 'demo' }),
  /insuffisant/,
)
// Coming back online cancels the pending backoff so the queue is retried right away.
navigator.onLine = true
globalThis.testBackend = {
  recordSale: async () => {
    throw new Error('Failed to fetch')
  },
}
await offline.syncPendingSales()
assert.ok(offline.nextSyncRetryAt() > now)
assert.equal(timers.size, 1)
window.dispatchEvent(new Event('online'))
assert.equal(offline.nextSyncRetryAt(), 0)
assert.equal(timers.size, 0)
navigator.onLine = false
// First launch offline: no cache yet, an empty list rather than an error.
productsFail = new Error('Failed to fetch')
assert.deepEqual(await covi.listProducts('never-cached', false, true), [])
console.log(
  'PASS listProducts caches the active stock including test products and serves it offline (mocked Supabase).',
)
console.log(
  'PASS offline reservation, oversell prevention, network retry with exponential backoff and no sync loop, stable operation id, concurrent sync exclusion, server rejection kept with its reason and stock restoration, per-account queue (mocked RPC).',
)
