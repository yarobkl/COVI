import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fcfa } from '../../lib/format'
import {
  fetchArrivalProfitability,
  fetchEstimatedProfit,
  type ArrivalProfitability,
  type EstimatedProfit,
} from '../../lib/insights'
import { liveStatistics, type Statistics } from '../../lib/operations'
import { lastMonths } from './bilanMath'
import { StatisticsPage } from './StatisticsPage'

vi.mock('../../lib/operations', () => ({ liveStatistics: vi.fn() }))
vi.mock('../../lib/insights', async (actual) => ({
  ...(await actual<typeof import('../../lib/insights')>()),
  fetchArrivalProfitability: vi.fn(),
  fetchEstimatedProfit: vi.fn(),
}))

const months = lastMonths(new Date())
const midMonth = (key: string) => {
  const [y, m] = key.split('-').map(Number)
  return new Date(y, m - 1, 15, 12).toISOString()
}
const sale = (key: string, amount: number, isTest = false) => ({
  total_amount: amount,
  sold_at: midMonth(key),
  is_test: isTest,
  sale_items: [{ quantity: 1, products: { category: 'Robes' } }],
})

const stats = (withExamples = false): Statistics =>
  ({
    from: new Date(),
    sales: [
      sale(months[0].key, 300000),
      sale(months[1].key, 400000),
      sale(months[2].key, 500000),
      ...(withExamples ? [sale(months[2].key, 99000, true)] : []),
    ],
    expenses: months.map((m) => ({ amount: 100000, expense_date: `${m.key}-05`, is_test: false })),
  }) as unknown as Statistics

const arrival: ArrivalProfitability = {
  arrivalId: 'a1',
  code: 'BAL-003',
  kind: 'balloon',
  status: 'received',
  originCountry: 'Belgique',
  supplierName: null,
  orderDate: null,
  receivedDate: '2026-08-02',
  isTest: false,
  cost: 250000,
  revenue: 186000,
  profit: -64000,
  recoveryPercent: 74,
  remainingToRecover: 64000,
  soldUnits: 31,
  remainingUnits: 19,
  productCount: 50,
}

const estimate = (from: string, revenue: number, cost: number, extra = 0): EstimatedProfit => ({
  timeZone: 'Africa/Brazzaville',
  from,
  to: null,
  revenue: revenue + extra,
  costOfGoodsSold: cost,
  grossProfit: revenue + extra - cost,
  charges: 100000,
  netProfit: revenue + extra - cost - 100000,
  revenueWithoutCost: 0,
  unsoldStockCost: 0,
  unallocatedArrivalCost: 0,
})
const revenues: Record<string, [number, number]> = {
  [`${months[0].key}-01`]: [300000, 120000],
  [`${months[1].key}-01`]: [400000, 150000],
  [`${months[2].key}-01`]: [500000, 200000],
}

beforeEach(() => {
  vi.mocked(liveStatistics).mockResolvedValue(stats())
  vi.mocked(fetchArrivalProfitability).mockResolvedValue([arrival])
  vi.mocked(fetchEstimatedProfit).mockImplementation(async (_id, period = {}, opts = {}) => {
    const [revenue, cost] = revenues[period.from!]
    // Examples add one sale of 99 000 to the last month.
    const extra = opts.includeTest && period.from === `${months[2].key}-01` ? 99000 : 0
    return estimate(period.from!, revenue, cost, extra)
  })
})
afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

const profitTable = () =>
  screen.getByRole('table', { name: 'Coût des articles vendus et bénéfice estimé, par mois' })

describe('StatisticsPage: the estimated profit', () => {
  it('gives it month by month when the database computes it', async () => {
    render(<StatisticsPage shopId="shop-1" />)
    const table = within(await screen.findByRole('table', { name: /bénéfice estimé/ }))
    const total = table.getByRole('row', { name: /^Total/ })
    expect(total.textContent).toContain(fcfa(-470000))
    expect(total.textContent).toContain(fcfa(1200000 - 470000 - 300000))
    expect(screen.getByText(/pour un ballon : son prix ÷ les pièces enregistrées/)).toBeTruthy()
    expect(screen.queryByText(/provisoire/)).toBeNull()
    // One call per complete month, local bounds, examples left out.
    expect(vi.mocked(fetchEstimatedProfit).mock.calls.map((c) => [c[1], c[2]])).toEqual(
      months.map((m) => [expect.objectContaining({ from: `${m.key}-01` }), { includeTest: false }]),
    )
    // Arrivals come from fetchArrivalProfitability.
    expect(screen.getByText('BAL-003')).toBeTruthy()
    expect(screen.getByText(/Encore/).textContent).toContain(fcfa(64000))
  })

  it.each([
    ['the database functions are not there yet', () => Promise.resolve(null)],
    ['the estimate fails', () => Promise.reject(new Error('Failed to fetch'))],
  ])('keeps a provisional « Reste après charges » when %s', async (_, answer) => {
    vi.mocked(fetchEstimatedProfit).mockImplementation(answer)
    render(<StatisticsPage shopId="shop-1" />)
    expect(await screen.findByText('Repère provisoire.')).toBeTruthy()
    expect(
      screen.getByText(/Sans compter ce que les articles vous ont coûté à l’achat/),
    ).toBeTruthy()
    expect(screen.queryByRole('table', { name: /bénéfice estimé/ })).toBeNull()
    // « Reste après charges » is never called a profit.
    expect(document.body.textContent).not.toMatch(/bénéfice|profit/i)
    expect(screen.getByText('BAL-003')).toBeTruthy()
  })

  it('counts the examples only once switched on', async () => {
    vi.mocked(liveStatistics).mockResolvedValue(stats(true))
    render(<StatisticsPage shopId="shop-1" />)
    await screen.findByRole('table', { name: /bénéfice estimé/ })
    const lastNet = () =>
      within(profitTable()).getAllByRole('row')[3].querySelectorAll('td')[1].textContent
    expect(lastNet()).toBe(fcfa(200000))
    fireEvent.click(screen.getByRole('switch', { name: 'Inclure la boutique d’exemple' }))
    expect(lastNet()).toBe(fcfa(299000))
  })

  it('shows the calm error when the Bilan cannot load', async () => {
    vi.mocked(liveStatistics).mockRejectedValue(new Error('Failed to fetch'))
    render(<StatisticsPage shopId="shop-1" />)
    expect(await screen.findByText('Le bilan ne s’affiche pas : pas de réseau.')).toBeTruthy()
  })
})
