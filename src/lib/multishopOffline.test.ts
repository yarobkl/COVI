import { beforeEach, describe, expect, it, vi } from 'vitest'

// The real offline queue (lib/offline.ts, unchanged) with the server call mocked.
const recordSale = vi.fn()
vi.mock('./covi', () => ({ recordSale }))

const offline = await import('./offline')
const { rememberActiveShop, readActiveShop } = await import('./activeShop')

const shop = (id: string) => ({ id, name: id, city: null, country: 'Congo', currency: 'XAF' })

beforeEach(() => {
  localStorage.clear()
  recordSale.mockReset()
  offline.setSyncUser('u1')
})

describe('offline queue with several shops', () => {
  it('a sale waiting on shop A stays on A while shop B is open, and is sent to A', async () => {
    offline.cacheStock('shop-a', [{ id: 'p-a', quantity_on_hand: 3 }])
    offline.cacheStock('shop-b', [{ id: 'p-b', quantity_on_hand: 5 }])
    rememberActiveShop('u1', shop('shop-a'))
    offline.queueSale({
      shopId: 'shop-a',
      productId: 'p-a',
      quantity: 1,
      soldUnitPrice: 5000,
      paymentLabel: 'cash',
      userId: 'u1',
    })
    // The owner switches to shop B (network still off).
    rememberActiveShop('u1', shop('shop-b'))
    expect(readActiveShop('u1')).toBe('shop-b')
    expect(offline.pendingSales().map((x) => x.shopId)).toEqual(['shop-a'])
    // B's stock kept on the phone is not touched by A's sale.
    expect(offline.cachedStock<{ id: string; quantity_on_hand: number }>('shop-b')).toEqual([
      { id: 'p-b', quantity_on_hand: 5 },
    ])
    // Network back while B is open: the sale is recorded for A, never moved to B.
    recordSale.mockResolvedValue('sale-1')
    const result = await offline.syncPendingSales()
    expect(result.synced).toBe(1)
    expect(recordSale).toHaveBeenCalledTimes(1)
    expect(recordSale.mock.calls[0][0]).toBe('shop-a')
    expect(offline.pendingSales()).toEqual([])
  })

  it('suspended meanwhile: the sale of A is kept with its reason, not retried', async () => {
    offline.queueSale({
      shopId: 'shop-a',
      productId: 'p-a',
      quantity: 1,
      soldUnitPrice: 5000,
      paymentLabel: 'cash',
      userId: 'u1',
    })
    rememberActiveShop('u1', shop('shop-b'))
    recordSale.mockRejectedValue({
      code: 'P0001',
      message: 'Subscription inactive: shop is read-only',
    })
    const result = await offline.syncPendingSales()
    expect(result.rejected).toBe(1)
    expect(offline.rejectedSales()).toMatchObject([
      { shopId: 'shop-a', reason: 'Subscription inactive: shop is read-only' },
    ])
  })
})
