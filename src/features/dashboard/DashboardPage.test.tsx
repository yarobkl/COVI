import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { dashboard } from '../../lib/operations'
import { DashboardPage } from './DashboardPage'

vi.mock('../../lib/operations', () => ({ dashboard: vi.fn() }))

afterEach(cleanup)

const summary = {
  todaySales: 36000,
  monthSales: 36000,
  charges: 70000,
  arrivalCost: 0,
  stock: 1,
  profitBeforeCharges: 36000,
  profit: -34000,
  saleCount: 1,
  arrivalsInProgress: 2,
  ordersInProgress: 1,
  balloonsInProgress: 1,
}

describe('DashboardPage', () => {
  it('shows an error with a retry button instead of loading forever', async () => {
    vi.mocked(dashboard)
      .mockRejectedValueOnce(new Error('Failed to fetch'))
      .mockResolvedValueOnce(summary)
    render(<DashboardPage shopId="shop-1" />)
    expect(screen.getByText('Chargement du commerce…')).toBeTruthy()
    expect(await screen.findByText(/Impossible de charger le tableau de bord/)).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }))
    expect(await screen.findByText('Tableau de bord')).toBeTruthy()
    expect(dashboard).toHaveBeenCalledTimes(2)
    expect(dashboard).toHaveBeenLastCalledWith('shop-1')
    // Singular agreement for one sale and one article.
    expect(screen.getByText('1 vente')).toBeTruthy()
    expect(screen.getByText('article')).toBeTruthy()
  })
})
