import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'

// Test the production offline module with browser storage and RPC outcomes controlled.
const values = new Map()
globalThis.localStorage = { getItem: k => values.get(k) ?? null, setItem: (k, v) => values.set(k, String(v)), removeItem: k => values.delete(k) }
globalThis.window = new EventTarget()
Object.defineProperty(globalThis, 'navigator', { value: { onLine: false }, configurable: true })
// Controlled clock and timers so the sync backoff can be observed without waiting.
let now = 1_000_000
Date.now = () => now
const timers = new Map()
let timerSeq = 0
globalThis.setTimeout = (fn, ms) => { const id = ++timerSeq; timers.set(id, { fn, at: now + ms }); return id }
globalThis.clearTimeout = id => { timers.delete(id) }
const fireTimers = async () => { const due = [...timers].filter(([, t]) => t.at <= now); for (const [id, t] of due) { timers.delete(id); t.fn() } await new Promise(r => setImmediate(r)) }
let syncEvents = 0
window.addEventListener('covi-sync', () => syncEvents++)
const source = await readFile(new URL('../src/lib/offline.ts', import.meta.url), 'utf8')
const compiled = stripTypeScriptTypes(source)
const moduleSource = compiled.replaceAll("await import('./covi')", 'globalThis.testBackend')
const offline = await import('data:text/javascript;base64,' + Buffer.from(moduleSource).toString('base64'))
const input = { shopId: 'test-shop', productId: 'test-product', quantity: 1, soldUnitPrice: 15000, paymentLabel: 'Espèces' }
const seed = () => offline.cacheStock(input.shopId, [{ id: input.productId, quantity_on_hand: 1, status: 'active' }])
seed()
assert.deepEqual(await offline.resilientSale(input), { offline: true })
assert.equal(offline.pendingCount(), 1)
assert.equal(offline.cachedStock(input.shopId)[0].quantity_on_hand, 0)
assert.equal(offline.cachedStock(input.shopId)[0].status, 'sold')
await assert.rejects(offline.resilientSale(input), /insuffisant/)
const operation = offline.pendingSales()[0].id
navigator.onLine = true
let failures = 0
globalThis.testBackend = { recordSale: async () => { failures++; throw new Error('Failed to fetch') } }
// A SyncStatus-like listener re-syncs on every covi-sync event: a network failure must not loop.
const resync = () => { if (navigator.onLine && offline.pendingCount() > 0) void offline.syncPendingSales() }
window.addEventListener('covi-sync', resync)
syncEvents = 0
await offline.syncPendingSales()
await new Promise(r => setImmediate(r))
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
for (let i = 0; i < 8; i++) { now = offline.nextSyncRetryAt(); await fireTimers(); delays.push(offline.nextSyncRetryAt() - now); assert.equal(timers.size, 1, 'a single retry timer') }
assert.deepEqual(delays, [10000, 20000, 40000, 80000, 160000, 300000, 300000, 300000])
assert.equal(failures, 9)
assert.equal(offline.pendingSales()[0].attempts, 9)
window.removeEventListener('covi-sync', resync)
let calls = 0
globalThis.testBackend = { recordSale: async (...args) => { calls++; assert.equal(args[5], operation) } }
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
globalThis.testBackend = { recordSale: async () => { throw new Error('Insufficient stock') } }
const rejected = await offline.syncPendingSales()
assert.equal(rejected.rejected, 1)
assert.equal(offline.pendingCount(), 0)
assert.equal(offline.cachedStock(input.shopId)[0].quantity_on_hand, 1)
assert.equal(offline.cachedStock(input.shopId)[0].status, 'active')
assert.equal(offline.rejectedSaleCount(), 1)
console.log('PASS offline reservation, oversell prevention, network retry with exponential backoff and no sync loop, stable operation id, concurrent sync exclusion, server rejection and stock restoration (mocked RPC).')
