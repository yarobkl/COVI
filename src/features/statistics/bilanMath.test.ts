import { describe, expect, it } from 'vitest'
import type { ArrivalProfit, Statistics } from '../../lib/operations'
import {
  arrivalResults,
  bilanTotal,
  hasExamples,
  lastMonths,
  monthlyBilan,
  topCategories,
} from './bilanMath'

const now = new Date(2026, 9, 8, 15, 0)
const at = (m: number, d: number, h = 12) => new Date(2026, m, d, h).toISOString()
const sale = (
  sold_at: string,
  total: number,
  items: [string | null, number][],
  is_test = false,
) => ({
  sold_at,
  total_amount: total,
  is_test,
  sale_items: items.map(([category, quantity]) => ({
    quantity,
    products: { category },
  })),
})

const stats: Pick<Statistics, 'sales' | 'expenses'> = {
  sales: [
    sale(at(6, 1, 0), 18000, [['Robes', 1]]), // 1er juillet, minuit passé : juillet
    sale(at(6, 20), 24000, [['Chemises', 2]]),
    sale(at(7, 15), 40000, [
      ['Robes', 1],
      ['Ensembles', 1],
    ]),
    sale(at(8, 30, 23), 22000, [['Jeans', 1]]), // 30 septembre, 23 h : septembre (heure locale)
    sale(at(8, 12), 50000, [['Robes', 5]], true), // exemple
    sale(at(9, 2), 15000, [['Friperie', 1]]), // octobre : pas dans le bilan
    sale(at(7, 3), 9000, [[null, 1]]),
  ],
  expenses: [
    { amount: 70000, expense_date: '2026-07-02', is_test: false },
    { amount: 25000, expense_date: '2026-09-05', is_test: false },
    { amount: 9999, expense_date: '2026-09-06', is_test: true },
    { amount: 90000, expense_date: '2026-10-02', is_test: false },
  ],
}

describe('bilan months', () => {
  it('takes the three complete months before this one', () => {
    expect(lastMonths(now)).toEqual([
      { key: '2026-07', label: 'juillet' },
      { key: '2026-08', label: 'août' },
      { key: '2026-09', label: 'septembre' },
    ])
    expect(lastMonths(new Date(2026, 1, 10)).map((m) => m.key)).toEqual([
      '2025-11',
      '2025-12',
      '2026-01',
    ])
  })

  it('adds sales and charges per local month, examples left out', () => {
    const rows = monthlyBilan(stats, lastMonths(now), false)
    expect(rows.map((r) => [r.key, r.sales, r.count, r.charges, r.rest])).toEqual([
      ['2026-07', 42000, 2, 70000, -28000],
      ['2026-08', 49000, 2, 0, 49000],
      ['2026-09', 22000, 1, 25000, -3000],
    ])
    expect(bilanTotal(rows)).toEqual({ sales: 113000, count: 5, charges: 95000, rest: 18000 })
  })

  it('counts the example shop only when asked', () => {
    const september = monthlyBilan(stats, lastMonths(now), true)[2]
    expect(september).toMatchObject({ sales: 72000, count: 2, charges: 34999 })
  })
})

describe('what sells best', () => {
  it('counts pieces per category over the months, most first', () => {
    expect(topCategories(stats.sales, lastMonths(now), false)).toEqual([
      { category: 'Chemises', pieces: 2 },
      { category: 'Robes', pieces: 2 },
      { category: 'Autre', pieces: 1 },
      { category: 'Ensembles', pieces: 1 },
      { category: 'Jeans', pieces: 1 },
    ])
    expect(topCategories(stats.sales, lastMonths(now), true, 1)).toEqual([
      { category: 'Robes', pieces: 7 },
    ])
  })
})

const arrival = (id: string, extra: Partial<ArrivalProfit>): ArrivalProfit =>
  ({
    id,
    code: id.toUpperCase(),
    kind: 'supplier_order',
    origin: 'Chine',
    supplier: null,
    status: 'received',
    is_test: false,
    cost: 100000,
    revenue: 0,
    profit: 0,
    recovery: 0,
    sold: 0,
    remaining: 0,
    productCount: 0,
    products: [],
    ...extra,
  }) as ArrivalProfit

describe('arrivals', () => {
  const profit = [
    arrival('bal-003', { kind: 'balloon', cost: 250000, revenue: 186000, recovery: 74 }),
    arrival('ind-002', { cost: 360000, revenue: 700000, recovery: 194 }),
    arrival('cmd-0412', { status: 'in_transit' }),
    arrival('ex-1', { is_test: true }),
  ]

  it('compares received arrivals and counts those not there yet', () => {
    const { shown, notReceived } = arrivalResults(profit, false)
    expect(shown.map((a) => a.code)).toEqual(['BAL-003', 'IND-002'])
    expect(shown[0]).toMatchObject({
      kind: 'balloon',
      cost: 250000,
      revenue: 186000,
      example: false,
    })
    expect(notReceived).toBe(1)
    expect(arrivalResults(profit, true).shown.map((a) => a.code)).toContain('EX-1')
  })

  it('offers the switch only when example data is there', () => {
    const base = { from: new Date(), ...stats, profit: profit.slice(0, 2) }
    expect(hasExamples(base)).toBe(true) // an example sale
    expect(
      hasExamples({
        ...base,
        sales: stats.sales.filter((s) => !s.is_test),
        expenses: stats.expenses.filter((e) => !e.is_test),
      }),
    ).toBe(false)
  })
})
