import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'

// Test the production offline module with browser storage and RPC outcomes controlled.
const values = new Map()
globalThis.localStorage = { getItem: k => values.get(k) ?? null, setItem: (k, v) => values.set(k, String(v)), removeItem: k => values.delete(k) }
globalThis.window = new EventTarget()
Object.defineProperty(globalThis, 'navigator', { value: { onLine: false }, configurable: true })
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
globalThis.testBackend = { recordSale: async () => { throw new Error('Failed to fetch') } }
await offline.syncPendingSales()
assert.equal(offline.pendingCount(), 1)
assert.equal(offline.pendingSales()[0].id, operation)
assert.equal(offline.pendingSales()[0].attempts, 1)
let calls = 0
globalThis.testBackend = { recordSale: async (...args) => { calls++; assert.equal(args[5], operation) } }
await Promise.all([offline.syncPendingSales(), offline.syncPendingSales()])
assert.equal(calls, 1)
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
console.log('PASS offline reservation, oversell prevention, network retry, stable operation id, concurrent sync exclusion, server rejection and stock restoration (mocked RPC).')
