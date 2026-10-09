import { cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import type { Shop } from '../lib/types'
import { App } from './App'

// The shell is tested on its own: pages are replaced by stubs showing their props.
vi.mock('../features/dashboard/DashboardPage', () => ({
  DashboardPage: ({ shopId }: { shopId: string }) => <p>page:dashboard:{shopId}</p>,
}))
vi.mock('../features/sale/SalePage', () => ({ SalePage: () => <p>page:sale</p> }))
vi.mock('../features/stock/StockPage', () => ({ StockPage: () => <p>page:stock</p> }))
vi.mock('../features/arrivals/ArrivalsPage', () => ({
  ArrivalsPage: ({ kind }: { kind?: string }) => <p>page:arrivals:{kind ?? 'all'}</p>,
}))
vi.mock('../features/expenses/ExpensesPage', () => ({ ExpensesPage: () => <p>page:expenses</p> }))
vi.mock('../features/history/HistoryPage', () => ({ HistoryPage: () => <p>page:history</p> }))
vi.mock('../features/statistics/StatisticsPage', () => ({
  StatisticsPage: () => <p>page:statistics</p>,
}))
vi.mock('../features/settings/SettingsPage', () => ({ SettingsPage: () => <p>page:settings</p> }))

afterEach(cleanup)

const shop: Shop = {
  id: 'shop-1',
  name: 'Boutique Élégance',
  city: 'Brazzaville',
  country: 'Congo',
  currency: 'XAF',
}

function renderApp(overrides: Partial<Shop> = {}) {
  const signOut = vi.fn().mockResolvedValue(undefined)
  const onSimulation = vi.fn()
  const view = render(
    <App
      shop={{ ...shop, ...overrides }}
      signOut={signOut}
      updateShop={vi.fn()}
      onSimulation={onSimulation}
    />,
  )
  const side = view.container.querySelector('aside nav') as HTMLElement
  const bottom = view.container.querySelector('.bottom') as HTMLElement
  return { ...view, side, bottom, signOut, onSimulation }
}

describe('App shell', () => {
  it('shows the shop, the navigation and the dashboard first', () => {
    const { side, bottom } = renderApp()
    expect(screen.getByText('Boutique Élégance')).toBeTruthy()
    expect(screen.getByText('Brazzaville · XAF')).toBeTruthy()
    expect(
      within(side)
        .getAllByRole('button')
        .map((b) => b.textContent),
    ).toEqual([
      'Tableau de bord',
      'Nouvelle vente',
      'Mon stock',
      'Mes arrivages',
      'Mes commandes',
      'Mes ballons',
      'Produits vendus',
      'Charges de la boutique',
      'Statistiques',
      'Paramètres',
    ])
    expect(
      within(bottom)
        .getAllByRole('button')
        .map((b) => b.textContent),
    ).toEqual(['Accueil', 'Vendre', 'Stock', 'Plus'])
    expect(screen.getByText('page:dashboard:shop-1')).toBeTruthy()
    expect(within(side).getByText('Tableau de bord').className).toBe('active')
  })

  it('falls back to a placeholder when the city is unknown', () => {
    renderApp({ city: null })
    expect(screen.getByText('Ville non renseignée · XAF')).toBeTruthy()
  })

  it('switches pages from the side navigation', () => {
    const { side } = renderApp()
    fireEvent.click(within(side).getByText('Mes commandes'))
    expect(screen.getByText('page:arrivals:supplier_order')).toBeTruthy()
    fireEvent.click(within(side).getByText('Mes ballons'))
    expect(screen.getByText('page:arrivals:balloon')).toBeTruthy()
    fireEvent.click(within(side).getByText('Paramètres'))
    expect(screen.getByText('page:settings')).toBeTruthy()
    expect(within(side).getByText('Paramètres').className).toBe('active')
    expect(within(side).getByText('Tableau de bord').className).toBe('')
  })

  it('switches pages from the bottom navigation', () => {
    const { bottom } = renderApp()
    fireEvent.click(within(bottom).getByText('Vendre'))
    expect(screen.getByText('page:sale')).toBeTruthy()
    fireEvent.click(within(bottom).getByText('Plus'))
    expect(screen.getByText('page:arrivals:all')).toBeTruthy()
    expect(within(bottom).getByText('Plus').className).toBe('active')
  })

  it('opens and closes the mobile menu', () => {
    const { container, side } = renderApp()
    const aside = container.querySelector('aside') as HTMLElement
    expect(aside.className).toBe('')
    fireEvent.click(container.querySelector('button.menub') as HTMLElement)
    expect(aside.className).toBe('open')
    fireEvent.click(within(side).getByText('Mon stock'))
    expect(aside.className).toBe('')
    expect(screen.getByText('page:stock')).toBeTruthy()
  })

  it('signs out and opens the simulation', () => {
    const { signOut, onSimulation } = renderApp()
    fireEvent.click(screen.getByTitle('Se déconnecter'))
    expect(signOut).toHaveBeenCalledTimes(1)
    fireEvent.click(screen.getByText('Découvrir la simulation · 3 mois'))
    expect(onSimulation).toHaveBeenCalledTimes(1)
  })
})
