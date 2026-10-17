import { describe, expect, it } from 'vitest'
import { OWNER, sellerKey, sellerTotals } from './sellerTotals'

const sale = (seller_id: string | null, total_amount: number, is_test = false) => ({
  seller_id,
  total_amount,
  is_test,
})

describe('Ventes par caissier', () => {
  it('groups the owner with the sales recorded before the team, then each cashier', () => {
    const names = new Map([
      ['u-awa', 'Awa'],
      ['u-bema', 'Bema'],
    ])
    const rows = sellerTotals(
      [
        sale(null, 5000),
        sale('u-owner', 2000),
        sale('u-awa', 9000),
        sale('u-awa', 4500),
        sale('u-bema', 1000),
        sale('u-bema', 99999, true),
        sale('u-gone', 300),
      ],
      'u-owner',
      names,
    )
    expect(rows).toEqual([
      { key: 'u-awa', name: 'Awa', count: 2, total: 13500 },
      { key: OWNER, name: 'Vous (responsable)', count: 2, total: 7000 },
      { key: 'u-bema', name: 'Bema', count: 1, total: 1000 },
      { key: 'u-gone', name: 'Ancien caissier', count: 1, total: 300 },
    ])
  })
  it('keys a sale by seller', () => {
    expect(sellerKey(null, 'u-owner')).toBe(OWNER)
    expect(sellerKey('u-owner', 'u-owner')).toBe(OWNER)
    expect(sellerKey('u-awa', 'u-owner')).toBe('u-awa')
  })
})
