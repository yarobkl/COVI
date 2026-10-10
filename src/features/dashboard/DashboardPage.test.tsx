import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { arrivalProfitability, dashboard, type Dashboard } from '../../lib/operations'
import type { Shop } from '../../lib/types'
import { DashboardPage } from './DashboardPage'

vi.mock('../../lib/operations', () => ({ dashboard: vi.fn(), arrivalProfitability: vi.fn() }))

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

beforeEach(() => {
  vi.mocked(arrivalProfitability).mockResolvedValue([])
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
})
