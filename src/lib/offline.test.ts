import 'fake-indexeddb/auto'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { deleteOfflineDb } from './idb'

// The IndexedDB mode of the offline store (tests/offline.mjs covers the queue logic in localStorage
// mode). Each test loads a fresh copy of offline.ts, as a page reload would.
type Offline = typeof import('./offline')
const recordSale = vi.fn()
vi.mock('./covi', () => ({ recordSale: (...args: unknown[]) => recordSale(...args) }))

let current: Offline | null = null
async function load(): Promise<Offline> {
  current?.closeOfflineStore()
  vi.resetModules()
  const offline = await import('./offline')
  await offline.initOfflineStore()
  current = offline
  return offline
}
const sale = (id: string, extra: Record<string, unknown> = {}) => ({
  id,
  shopId: 'shop',
  productId: 'p1',
  quantity: 1,
  soldUnitPrice: 5000,
  paymentLabel: 'Espèces',
  createdAt: '2026-10-01T10:00:00.000Z',
  attempts: 0,
  ...extra,
})
const online = (value: boolean) =>
  Object.defineProperty(navigator, 'onLine', { value, configurable: true })

beforeEach(async () => {
  current?.closeOfflineStore()
  current = null
  localStorage.clear()
  await deleteOfflineDb()
  recordSale.mockReset()
  online(true)
})
afterEach(() => vi.restoreAllMocks())

describe('migration localStorage → IndexedDB', () => {
  it('moves the queue, the refused sales and the stock without losing anything', async () => {
    localStorage.setItem(
      'covi:pending-sales:v1',
      JSON.stringify([sale('a', { userId: 'u1' }), sale('legacy-no-user')]),
    )
    localStorage.setItem(
      'covi:rejected-sales:v2',
      JSON.stringify([{ ...sale('r', { userId: 'u1' }), reason: 'Insufficient stock' }]),
    )
    localStorage.setItem('covi:rejected-sales:v1', '2')
    localStorage.setItem(
      'covi:stock:shop',
      JSON.stringify([{ id: 'p1', quantity_on_hand: 3, status: 'active' }]),
    )
    localStorage.setItem('covi:stock:shop:at', '2026-10-01T09:00:00.000Z')

    let offline = await load()
    expect(offline.offlineStorageMode()).toBe('indexeddb')
    offline.setSyncUser('u1')
    expect(offline.pendingSales().map((x) => x.id)).toEqual(['a', 'legacy-no-user'])
    expect(offline.rejectedSaleCount()).toBe(3)
    expect(offline.cachedStock('shop')).toEqual([
      { id: 'p1', quantity_on_hand: 3, status: 'active' },
    ])
    expect(offline.stockCacheDate('shop')).toBe('2026-10-01T09:00:00.000Z')
    // Copied keys are removed once the transaction is committed.
    expect(localStorage.getItem('covi:pending-sales:v1')).toBeNull()
    expect(localStorage.getItem('covi:rejected-sales:v2')).toBeNull()
    expect(localStorage.getItem('covi:rejected-sales:v1')).toBeNull()
    expect(localStorage.getItem('covi:stock:shop')).toBeNull()

    // Next launch: everything comes from IndexedDB.
    offline = await load()
    offline.setSyncUser('u1')
    expect(offline.pendingCount()).toBe(2)
    expect(offline.rejectedSales()[0].reason).toBe('Insufficient stock')
    expect(offline.cachedStock('shop')).toHaveLength(1)
  })

  it('keeps the IndexedDB record when localStorage still holds an older copy', async () => {
    let offline = await load()
    offline.setSyncUser('u1')
    offline.queueSale(
      {
        shopId: 'shop',
        productId: 'p1',
        quantity: 1,
        soldUnitPrice: 1,
        paymentLabel: 'Espèces',
        userId: 'u1',
      },
      'same-id',
    )
    await offline.flushOfflineStore()
    // An old tab (previous version) wrote the same sale to localStorage, plus a new one.
    localStorage.setItem(
      'covi:pending-sales:v1',
      JSON.stringify([
        sale('same-id', { attempts: 0, userId: 'u1' }),
        sale('from-old-tab', { userId: 'u1' }),
      ]),
    )
    offline = await load()
    offline.setSyncUser('u1')
    expect(
      offline
        .pendingSales()
        .map((x) => x.id)
        .sort(),
    ).toEqual(['from-old-tab', 'same-id'])
  })

  it('stays on localStorage when IndexedDB is unavailable', async () => {
    const saved = globalThis.indexedDB
    // @ts-expect-error simulate a WebView without IndexedDB
    delete globalThis.indexedDB
    try {
      const offline = await load()
      expect(offline.offlineStorageMode()).toBe('localstorage')
      offline.setSyncUser('u1')
      online(false)
      offline.cacheStock('shop', [{ id: 'p1', quantity_on_hand: 1, status: 'active' }])
      await expect(
        offline.resilientSale({
          shopId: 'shop',
          productId: 'p1',
          quantity: 1,
          soldUnitPrice: 1,
          paymentLabel: 'Espèces',
        }),
      ).resolves.toEqual({ offline: true })
      expect(JSON.parse(localStorage.getItem('covi:pending-sales:v1')!)).toHaveLength(1)
    } finally {
      globalThis.indexedDB = saved
    }
  })
})

describe('queue in IndexedDB', () => {
  it('persists an offline sale before confirming it', async () => {
    let offline = await load()
    offline.setSyncUser('u1')
    offline.cacheStock('shop', [{ id: 'p1', quantity_on_hand: 2, status: 'active' }])
    online(false)
    await expect(
      offline.resilientSale({
        shopId: 'shop',
        productId: 'p1',
        quantity: 1,
        soldUnitPrice: 1,
        paymentLabel: 'Espèces',
      }),
    ).resolves.toEqual({ offline: true })
    offline = await load()
    offline.setSyncUser('u1')
    expect(offline.pendingCount()).toBe(1)
    expect(offline.cachedStock<{ quantity_on_hand: number }>('shop')[0].quantity_on_hand).toBe(1)
  })

  it('keeps a sale added while a synchronisation is waiting for the server', async () => {
    let offline = await load()
    offline.setSyncUser('u1')
    offline.queueSale(
      {
        shopId: 'shop',
        productId: 'p1',
        quantity: 1,
        soldUnitPrice: 1,
        paymentLabel: 'Espèces',
        userId: 'u1',
      },
      'first',
    )
    let release: (value?: unknown) => void = () => {}
    recordSale.mockImplementationOnce(() => new Promise((resolve) => (release = resolve)))
    const running = offline.syncPendingSales()
    await vi.waitFor(() => expect(recordSale).toHaveBeenCalledTimes(1))
    offline.queueSale(
      {
        shopId: 'shop',
        productId: 'p1',
        quantity: 1,
        soldUnitPrice: 1,
        paymentLabel: 'Espèces',
        userId: 'u1',
      },
      'during-sync',
    )
    release()
    await running
    await offline.flushOfflineStore()
    expect(offline.pendingSales().map((x) => x.id)).toEqual(['during-sync'])
    offline = await load()
    offline.setSyncUser('u1')
    expect(offline.pendingSales().map((x) => x.id)).toEqual(['during-sync'])
  })

  it('moves a refused sale to the refused list in one transaction', async () => {
    let offline = await load()
    offline.setSyncUser('u1')
    offline.queueSale(
      {
        shopId: 'shop',
        productId: 'p1',
        quantity: 1,
        soldUnitPrice: 1,
        paymentLabel: 'Espèces',
        userId: 'u1',
      },
      'refused',
    )
    recordSale.mockRejectedValueOnce({ message: 'Insufficient stock', code: 'P0001' })
    expect(await offline.syncPendingSales()).toMatchObject({ synced: 0, rejected: 1 })
    await offline.flushOfflineStore()
    offline = await load()
    offline.setSyncUser('u1')
    expect(offline.pendingCount()).toBe(0)
    expect(offline.rejectedSales().map((x) => [x.id, x.reason])).toEqual([
      ['refused', 'Insufficient stock'],
    ])
  })

  it('shows a sale queued in another tab', async () => {
    const tabA = await load()
    current = null // keep tab A open
    const tabB = await load()
    tabA.setSyncUser('u1')
    tabB.setSyncUser('u1')
    tabA.queueSale(
      {
        shopId: 'shop',
        productId: 'p1',
        quantity: 1,
        soldUnitPrice: 1,
        paymentLabel: 'Espèces',
        userId: 'u1',
      },
      'from-tab-a',
    )
    await vi.waitFor(() => expect(tabB.pendingSales().map((x) => x.id)).toEqual(['from-tab-a']))
    tabA.closeOfflineStore()
  })

  it('remembers the last shop of each account', async () => {
    let offline = await load()
    await offline.rememberShop('u1', { id: 's1', name: 'Boutique' })
    offline = await load()
    expect(offline.cachedShop('u1')).toEqual({ id: 's1', name: 'Boutique' })
    expect(offline.cachedShop('u2')).toBeNull()
  })

  it('copies the sale to localStorage when IndexedDB refuses the write', async () => {
    vi.resetModules()
    vi.doMock('./idb', async (importOriginal) => {
      const real = await importOriginal<typeof import('./idb')>()
      return {
        ...real,
        openOfflineDb: async () => {
          const db = await real.openOfflineDb()
          return (
            db && {
              ...db,
              write: (ops: Parameters<typeof db.write>[0], strict?: boolean) =>
                ops.some((op) => op.store === 'pending')
                  ? Promise.reject(new DOMException('Quota exceeded', 'QuotaExceededError'))
                  : db.write(ops, strict),
            }
          )
        },
      }
    })
    vi.spyOn(console, 'warn').mockImplementation(() => {})
    const offline = await import('./offline')
    await offline.initOfflineStore()
    current = offline
    offline.setSyncUser('u1')
    offline.cacheStock('shop', [{ id: 'p1', quantity_on_hand: 1, status: 'active' }])
    online(false)
    await expect(
      offline.resilientSale({
        shopId: 'shop',
        productId: 'p1',
        quantity: 1,
        soldUnitPrice: 1,
        paymentLabel: 'Espèces',
      }),
    ).resolves.toEqual({ offline: true })
    expect(JSON.parse(localStorage.getItem('covi:pending-sales:v1')!)).toHaveLength(1)
    vi.doUnmock('./idb')
    // Next launch (IndexedDB working again): the copy is migrated.
    const next = await load()
    next.setSyncUser('u1')
    expect(next.pendingCount()).toBe(1)
    expect(localStorage.getItem('covi:pending-sales:v1')).toBeNull()
  })
})

describe('record_sale SQL permission failures', () => {
  it('does not retry a permanent shop ownership refusal (42501)', async () => {
    const offline = await load()
    expect(offline.isRetryableSyncError({ code: '42501', message: 'Shop not found' })).toBe(false)
    expect(
      offline.isRetryableSyncError({ code: '42501', message: 'permission denied for table sales' }),
    ).toBe(false)
    expect(offline.isRetryableSyncError({ code: '42501', message: 'Forbidden' })).toBe(false)
  })

  it('retries expired authentication only after a renewed session is possible', async () => {
    const offline = await load()
    expect(offline.isRetryableSyncError({ code: '42501', message: 'Authentication required' })).toBe(
      true,
    )
    expect(offline.isRetryableSyncError({ message: 'JWT expired' })).toBe(true)
    expect(offline.isRetryableSyncError({ message: 'Failed to fetch' })).toBe(true)
  })
})
