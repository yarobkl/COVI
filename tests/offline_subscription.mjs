import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { stripTypeScriptTypes } from 'node:module'

// Vente hors ligne enregistrée AVANT une suspension, synchronisée APRÈS (audit SaaS, PR #12).
// Vérifie, sans modifier src/lib/offline.ts, que l'erreur serveur
// P0001 « Subscription inactive: shop is read-only » est classée définitive :
// la vente quitte la file, elle est CONSERVÉE avec son motif (jamais supprimée en silence),
// le stock local est restauré et aucune boucle de réessai n'a lieu.
const values = new Map()
globalThis.localStorage = {
  getItem: (k) => values.get(k) ?? null,
  setItem: (k, v) => values.set(k, String(v)),
  removeItem: (k) => values.delete(k),
}
globalThis.window = new EventTarget()
Object.defineProperty(globalThis, 'navigator', { value: { onLine: false }, configurable: true })
const source = await readFile(new URL('../src/lib/offline.ts', import.meta.url), 'utf8')
const moduleSource = stripTypeScriptTypes(source).replaceAll(
  /await\s+import\(\s*'\.\/covi'\s*\)/g,
  'globalThis.testBackend',
)
assert.ok(!moduleSource.includes("'./covi'"), 'every backend import of offline.ts is mocked')
const offline = await import(
  'data:text/javascript;base64,' + Buffer.from(moduleSource).toString('base64')
)

const input = {
  shopId: 'shop-a',
  productId: 'robe-a',
  quantity: 1,
  soldUnitPrice: 5000,
  paymentLabel: 'Espèces',
}
offline.cacheStock(input.shopId, [{ id: input.productId, quantity_on_hand: 1, status: 'active' }])
offline.setSyncUser('owner-o')

// 1. Hors ligne, abonnement encore actif : la vente est mise en file.
assert.deepEqual(await offline.resilientSale(input), { offline: true })
assert.equal(offline.pendingCount(), 1)
const operation = offline.pendingSales()[0].id

// 2. Retour en ligne après la suspension : le serveur refuse (forme d'une PostgrestError).
navigator.onLine = true
let calls = 0
globalThis.testBackend = {
  recordSale: async (...args) => {
    calls++
    assert.equal(args[5], operation, 'même operation id rejoué')
    throw { message: 'Subscription inactive: shop is read-only', code: 'P0001' }
  },
}
const result = await offline.syncPendingSales()
assert.deepEqual(result, { synced: 0, pending: 0, rejected: 1 })
assert.equal(calls, 1)
assert.equal(offline.cachedStock(input.shopId)[0].quantity_on_hand, 1, 'stock local restauré')

// 3. Conservée et affichable, avec le motif exact et l'operation id (reprise possible).
const kept = offline.rejectedSales()
assert.equal(kept.length, 1)
assert.equal(kept[0].reason, 'Subscription inactive: shop is read-only')
assert.equal(kept[0].id, operation)
assert.equal(offline.rejectedSaleCount(), 1)

// 4. Pas de boucle : une nouvelle synchronisation ne rappelle pas le serveur.
await offline.syncPendingSales()
assert.equal(calls, 1)

console.log(
  'PASS offline sale queued before suspension and synced after: permanent rejection kept with reason "Subscription inactive: shop is read-only", stock restored, no retry loop.',
)
