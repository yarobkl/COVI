import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fcfa } from '../../lib/format'
import {
  fetchEstimatedProfit,
  fetchShopDashboard,
  type EstimatedProfit,
  type ShopDashboard,
} from '../../lib/insights'
import { arrivalProfitability, dashboard, type Dashboard } from '../../lib/operations'
import type { Shop } from '../../lib/types'
import { DashboardPage } from './DashboardPage'

vi.mock('../../lib/operations', () => ({ dashboard: vi.fn(), arrivalProfitability: vi.fn() }))
vi.mock('../../lib/insights', async (actual) => ({
  ...(await actual<typeof import('../../lib/insights')>()),
  fetchShopDashboard: vi.fn(),
  fetchEstimatedProfit: vi.fn(),
}))

const nbsp = String.fromCharCode(0xa0)
const shop: Shop = {
  id: 'shop-1',
  name: 'Chez Mama Grâce',
  city: 'Poto-Poto',
  country: 'Congo',
  currency: 'XAF',
}

const summary: Dashboard = {
  today: {
    total: 126000,
    count: 7,
    byMethod: [
      { method: 'cash', amount: 74000 },
      { method: 'mobile_money', amount: 52000 },
    ],
  },
  month: {
    total: 612000,
    count: 41,
    charges: 140000,
    expenses: [
      { category: 'Loyer', amount: 90000 },
      { category: 'Électricité', amount: 50000 },
    ],
    restAfterCharges: 472000,
  },
  previousMonth: { total: 854000, date: new Date(2026, 8, 1) },
  stock: 33,
  lowStock: [
    { id: 'p-b', name: 'Jean droit modèle B', quantity_on_hand: 1, is_unique_piece: false },
  ],
  arrivalsInProgress: [
    {
      id: 'a',
      code: 'CMD-0412',
      kind: 'supplier_order',
      status: 'in_transit',
      origin_country: 'Chine',
      order_date: '2026-09-28',
    },
  ],
  recentSales: [
    {
      id: 's1',
      soldAt: new Date().toISOString(),
      paymentMethod: 'mobile_money',
      total: 18000,
      lines: [{ quantity: 1, name: 'Robe wax modèle A', balloon: false }],
    },
  ],
}

/** shop_dashboard as the database (or its fallback) would give it for `d`. */
const figuresOf = (d: Dashboard): ShopDashboard => ({
  source: 'database',
  timeZone: 'Africa/Brazzaville',
  today: '2026-10-10',
  monthStart: '2026-10-01',
  todaySales: d.today.total,
  todayCount: d.today.count,
  todayByPaymentMethod: d.today.byMethod,
  monthSales: d.month.total,
  saleCount: d.month.count,
  previousMonthStart: '2026-09-01',
  previousMonthSales: d.previousMonth.total,
  charges: d.month.charges,
  expensesByCategory: d.month.expenses,
  restAfterCharges: d.month.restAfterCharges,
  arrivalCost: 0,
  stock: d.stock,
  profitBeforeCharges: 0,
  profit: 0,
  arrivalsInProgress: d.arrivalsInProgress.length,
  ordersInProgress: 0,
  balloonsInProgress: 0,
  inProgressByStatus: { draft: 0, ordered: 0, in_transit: 0 },
})

const estimate: EstimatedProfit = {
  timeZone: 'Africa/Brazzaville',
  from: '2026-10-01',
  to: '2026-11-01',
  revenue: 612000,
  costOfGoodsSold: 251000,
  grossProfit: 361000,
  charges: 140000,
  netProfit: 221000,
  revenueWithoutCost: 0,
  unsoldStockCost: 0,
  unallocatedArrivalCost: 0,
}

/** What a notebook line shows on its right. */
const lineValue = (label: string) =>
  screen.getByText(label).closest('li')?.querySelector('.ledger__value')?.textContent

beforeEach(() => {
  vi.mocked(arrivalProfitability).mockResolvedValue([])
  vi.mocked(fetchShopDashboard).mockImplementation(async (_id, _opts, base) =>
    figuresOf(await base!()),
  )
  vi.mocked(fetchEstimatedProfit).mockResolvedValue(null)
})
afterEach(cleanup)

describe('DashboardPage', () => {
  it('shows a calm error with a retry button instead of loading forever', async () => {
    vi.mocked(dashboard)
      .mockRejectedValueOnce(new Error('Failed to fetch'))
      .mockResolvedValueOnce(summary)
    render(<DashboardPage shop={shop} onSimulation={vi.fn()} />)
    expect(screen.getByText('On fait les comptes…')).toBeTruthy()
    expect(await screen.findByText('Les chiffres ne s’affichent pas : pas de réseau.')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }))
    expect(await screen.findByText('Aujourd’hui, la caisse a reçu')).toBeTruthy()
    expect(dashboard).toHaveBeenCalledTimes(2)
    expect(dashboard).toHaveBeenLastCalledWith('shop-1')
  })

  it('gives one hero figure, then the month in notebook lines', async () => {
    vi.mocked(dashboard).mockResolvedValue(summary)
    render(<DashboardPage shop={shop} onSimulation={vi.fn()} />)
    expect((await screen.findByText(/^126/)).textContent).toBe(`126${nbsp}000FCFA`)
    expect(screen.getByText('7 ventes')).toBeTruthy()
    expect(
      screen.getByRole('img', {
        name: `Espèces 74${nbsp}000${nbsp}FCFA, Mobile Money 52${nbsp}000${nbsp}FCFA`,
      }),
    ).toBeTruthy()
    expect(screen.getByText('Reste après charges')).toBeTruthy()
    expect(screen.getByText(/Sans compter ce que les articles vous ont coûté/)).toBeTruthy()
    expect(screen.getByText('plus que 1')).toBeTruthy()
    expect(screen.getByText('En route')).toBeTruthy()
    expect(document.querySelectorAll('.kpi')).toHaveLength(0)
  })

  it('says so when nothing was sold today yet', async () => {
    vi.mocked(dashboard).mockResolvedValue({
      ...summary,
      today: { total: 0, count: 0, byMethod: [] },
    })
    render(<DashboardPage shop={shop} onSimulation={vi.fn()} />)
    expect(await screen.findByText('Pas encore de vente aujourd’hui.')).toBeTruthy()
  })

  it('guides a brand new shop', async () => {
    const onSimulation = vi.fn()
    vi.mocked(dashboard).mockResolvedValue({
      ...summary,
      today: { total: 0, count: 0, byMethod: [] },
      month: { total: 0, count: 0, charges: 0, expenses: [], restAfterCharges: 0 },
      stock: 0,
      lowStock: [],
      arrivalsInProgress: [],
      recentSales: [],
    })
    render(<DashboardPage shop={shop} onSimulation={onSimulation} />)
    expect(await screen.findByText('Chez Mama Grâce est prête.')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Voir d’abord une boutique d’exemple' }))
    expect(onSimulation).toHaveBeenCalled()
  })

  describe('the month', () => {
    it('gives the estimated profit when the database computes it', async () => {
      vi.mocked(dashboard).mockResolvedValue(summary)
      vi.mocked(fetchEstimatedProfit).mockResolvedValue(estimate)
      render(<DashboardPage shop={shop} onSimulation={vi.fn()} />)
      expect(await screen.findByText('Bénéfice estimé')).toBeTruthy()
      expect(lineValue('Coût des articles vendus')).toBe(fcfa(-251000))
      expect(lineValue('Loyer')).toBe(fcfa(-90000))
      expect(lineValue('Bénéfice estimé')).toBe(fcfa(221000))
      expect(screen.getByText(/pour un ballon : son prix ÷ les pièces enregistrées/)).toBeTruthy()
      expect(screen.queryByText('Reste après charges')).toBeNull()
      expect(screen.queryByText(/provisoire/)).toBeNull()
      // This month only, in the shop's time zone, examples left out.
      const [shopId, period] = vi.mocked(fetchEstimatedProfit).mock.calls[0]
      expect(shopId).toBe('shop-1')
      expect(period?.from).toMatch(/^\d{4}-\d{2}-01$/)
      expect(period?.to).toMatch(/^\d{4}-\d{2}-01$/)
    })

    it.each([
      ['the database functions are not there yet', () => Promise.resolve(null)],
      ['the estimate fails', () => Promise.reject(new Error('Failed to fetch'))],
    ])('keeps a provisional « Reste après charges » when %s', async (_, answer) => {
      vi.mocked(dashboard).mockResolvedValue(summary)
      vi.mocked(fetchEstimatedProfit).mockImplementation(answer)
      render(<DashboardPage shop={shop} onSimulation={vi.fn()} />)
      expect(await screen.findByText('Reste après charges')).toBeTruthy()
      expect(lineValue('Reste après charges')).toBe(fcfa(472000))
      expect(screen.getByText('Repère provisoire.')).toBeTruthy()
      expect(
        screen.getByText(/Sans compter ce que les articles vous ont coûté à l’achat/),
      ).toBeTruthy()
      // Never called a profit.
      expect(document.body.textContent).not.toMatch(/bénéfice|profit/i)
      expect(screen.getByText('Aujourd’hui, la caisse a reçu')).toBeTruthy()
    })

    it('shows the calm error when the month cannot be counted', async () => {
      vi.mocked(dashboard).mockResolvedValue(summary)
      vi.mocked(fetchShopDashboard).mockRejectedValue(new Error('Failed to fetch'))
      render(<DashboardPage shop={shop} onSimulation={vi.fn()} />)
      expect(
        await screen.findByText('Les chiffres ne s’affichent pas : pas de réseau.'),
      ).toBeTruthy()
    })
  })
})
