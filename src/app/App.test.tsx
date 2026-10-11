import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react'
import { useState } from 'react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Shop } from '../lib/types'
import { App } from './App'

// The shell is tested on its own: pages are replaced by stubs showing their props.
vi.mock('../features/dashboard/DashboardPage', () => ({
  DashboardPage: ({ shop }: { shop: { id: string } }) => <p>page:dashboard:{shop.id}</p>,
}))
vi.mock('../features/sale/SalePage', () => ({ SalePage: () => <p>page:sale</p> }))
vi.mock('../features/stock/StockPage', () => ({ StockPage: () => <p>page:stock</p> }))
vi.mock('../features/arrivals/ArrivalsPage', () => ({
  // Keeps a counter, to check that each filter has its own state.
  ArrivalsPage: ({ kind }: { kind?: string }) => {
    const [n, setN] = useState(0)
    return (
      <button type="button" onClick={() => setN(n + 1)}>
        page:arrivals:{kind ?? 'all'}:{n}
      </button>
    )
  },
}))
vi.mock('../features/expenses/ExpensesPage', () => ({ ExpensesPage: () => <p>page:expenses</p> }))
vi.mock('../features/history/HistoryPage', () => ({ HistoryPage: () => <p>page:history</p> }))
vi.mock('../features/statistics/StatisticsPage', () => ({
  StatisticsPage: () => <p>page:statistics</p>,
}))
vi.mock('../features/settings/SettingsPage', () => ({ SettingsPage: () => <p>page:settings</p> }))
vi.mock('../features/auth/useCurrentUser', () => ({ useCurrentUser: () => null }))

const shop: Shop = {
  id: 'shop-1',
  name: 'Chez Mama Grâce',
  city: 'Poto-Poto, Brazzaville',
  country: 'Congo',
  currency: 'XAF',
}

beforeEach(() => {
  window.location.hash = ''
  localStorage.clear()
})
afterEach(cleanup)

async function go(hash: string) {
  await act(async () => {
    window.location.hash = hash
    await new Promise((r) => setTimeout(r, 0))
  })
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
  const sommaire = screen.getByRole('navigation', { name: 'Sommaire' })
  const bottom = screen.getByRole('navigation', { name: 'Navigation principale' })
  return { ...view, sommaire, bottom, signOut, onSimulation }
}

describe('App shell', () => {
  it('shows the notebook label, the navigation and Accueil first', () => {
    const { sommaire, bottom } = renderApp()
    expect(within(sommaire).getByText('Chez Mama Grâce')).toBeTruthy()
    expect(within(sommaire).getByText('Poto-Poto, Brazzaville')).toBeTruthy()
    expect(
      within(sommaire)
        .getAllByRole('link')
        .map((a) => a.textContent),
    ).toEqual([
      'Nouvelle vente',
      'Accueil',
      'Stock',
      'Arrivages',
      'Ventes',
      'Charges',
      'Bilan',
      'Ma boutique',
    ])
    expect(
      within(bottom)
        .getAllByRole('link')
        .map((a) => a.textContent),
    ).toEqual(['Accueil', 'Vendre', 'Stock'])
    expect(within(bottom).getByRole('button', { name: 'Plus' })).toBeTruthy()
    expect(screen.getByText('page:dashboard:shop-1')).toBeTruthy()
    expect(
      within(sommaire).getByRole('link', { name: 'Accueil' }).getAttribute('aria-current'),
    ).toBe('page')
  })

  it('uses the real initials, never a hard-coded badge', () => {
    renderApp()
    expect(screen.getByRole('button', { name: 'Ma boutique' }).textContent).toBe('MG')
  })

  it('asks to add the city when it is unknown', () => {
    const { sommaire } = renderApp({ city: null })
    expect(
      within(sommaire).getByRole('link', { name: 'Ajouter la ville' }).getAttribute('href'),
    ).toBe('#/boutique')
  })

  it('follows the URL hash, with its own state for each arrival filter', async () => {
    const { bottom } = renderApp()
    expect(within(bottom).getByRole('link', { name: 'Vendre' }).getAttribute('href')).toBe(
      '#/vendre',
    )
    await go('#/vendre')
    expect(screen.getByText('page:sale')).toBeTruthy()
    expect(within(bottom).getByRole('link', { name: 'Vendre' }).getAttribute('aria-current')).toBe(
      'page',
    )
    await go('#/arrivages/ballons')
    fireEvent.click(screen.getByText('page:arrivals:balloon:0'))
    expect(screen.getByText('page:arrivals:balloon:1')).toBeTruthy()
    await go('#/arrivages/commandes')
    expect(screen.getByText('page:arrivals:supplier_order:0')).toBeTruthy()
    await go('#/arrivages')
    expect(screen.getByText('page:arrivals:all:0')).toBeTruthy()
    expect(
      screen
        .getByRole('navigation', { name: 'Filtrer les arrivages' })
        .querySelector('[aria-current="page"]')?.textContent,
    ).toBe('Tous')
    await go('#/boutique')
    expect(screen.getByText('page:settings')).toBeTruthy()
    expect(document.title).toBe('Ma boutique · COVI')
  })

  it('opens the menu from « Plus » and signs out only after confirmation', async () => {
    const { bottom, signOut } = renderApp()
    fireEvent.click(within(bottom).getByRole('button', { name: 'Plus' }))
    const menu = screen.getByRole('dialog', { name: 'Menu' })
    expect(
      within(menu)
        .getAllByRole('link')
        .map((a) => a.textContent),
    ).toContain('Charges')
    fireEvent.click(within(menu).getByRole('button', { name: 'Se déconnecter' }))
    const confirm = screen.getByRole('dialog', { name: 'Se déconnecter de Chez Mama Grâce ?' })
    fireEvent.click(within(confirm).getByRole('button', { name: 'Rester' }))
    expect(signOut).not.toHaveBeenCalled()

    fireEvent.click(screen.getAllByRole('button', { name: 'Se déconnecter' })[0])
    await act(async () => {
      fireEvent.click(
        within(screen.getByRole('dialog', { name: /Se déconnecter de/ })).getByRole('button', {
          name: 'Se déconnecter',
        }),
      )
    })
    expect(signOut).toHaveBeenCalledTimes(1)
  })

  it('warns before signing out with sales still on the phone', () => {
    localStorage.setItem(
      'covi:pending-sales:v1',
      JSON.stringify([{ id: 'op-1', shopId: 'shop-1', productId: 'p1', quantity: 1 }]),
    )
    renderApp()
    fireEvent.click(screen.getAllByRole('button', { name: 'Se déconnecter' })[0])
    const confirm = screen.getByRole('dialog', { name: /Se déconnecter de/ })
    expect(confirm.textContent).toContain('1 vente n’est pas encore envoyée.')
    expect(within(confirm).getByRole('button', { name: 'Attendre' })).toBeTruthy()
    expect(within(confirm).getByRole('button', { name: 'Me déconnecter quand même' })).toBeTruthy()
  })

  it('opens the example shop', () => {
    const { onSimulation, sommaire } = renderApp()
    fireEvent.click(within(sommaire).getByRole('button', { name: 'Voir une boutique d’exemple' }))
    expect(onSimulation).toHaveBeenCalledTimes(1)
  })
})

describe('App shell: several shops and read only', () => {
  const READ_ONLY =
    'Abonnement suspendu : vous pouvez consulter vos données, mais plus vendre ni modifier. Contactez COVI pour le renouveler.'

  function renderWith(account: Parameters<typeof App>[0]['account']) {
    render(
      <App
        shop={shop}
        signOut={vi.fn().mockResolvedValue(undefined)}
        updateShop={vi.fn()}
        onSimulation={vi.fn()}
        account={account}
      />,
    )
    return {
      sommaire: screen.getByRole('navigation', { name: 'Sommaire' }),
      bottom: screen.getByRole('navigation', { name: 'Navigation principale' }),
    }
  }

  it('one shop: no « Changer de boutique »; adding a shop is offered', () => {
    const addShop = vi.fn()
    const { sommaire } = renderWith({ shopCount: 1, addShop, readOnly: false })
    expect(within(sommaire).queryByRole('button', { name: 'Changer de boutique' })).toBeNull()
    fireEvent.click(within(sommaire).getByRole('button', { name: 'Ajouter une boutique' }))
    expect(addShop).toHaveBeenCalledTimes(1)
  })

  it('several shops: « Changer de boutique » in the Sommaire and in the « Ma boutique » menu', () => {
    const switchShop = vi.fn()
    const { sommaire } = renderWith({
      shopCount: 2,
      switchShop,
      addShop: vi.fn(),
      readOnly: false,
    })
    fireEvent.click(within(sommaire).getByRole('button', { name: 'Changer de boutique' }))
    expect(switchShop).toHaveBeenCalledTimes(1)
    fireEvent.click(screen.getByRole('button', { name: 'Ma boutique' }))
    const menu = screen.getByRole('dialog')
    fireEvent.click(within(menu).getByRole('button', { name: 'Changer de boutique' }))
    expect(switchShop).toHaveBeenCalledTimes(2)
  })

  it('adding a shop impossible: the button is disabled and says why', () => {
    const { sommaire } = renderWith({
      shopCount: 1,
      addShopBlocked: 'Votre abonnement est suspendu. Contactez COVI pour le renouveler.',
      readOnly: true,
    })
    const add = within(sommaire).getByRole('button', {
      name: 'Ajouter une boutique',
    }) as HTMLButtonElement
    expect(add.disabled).toBe(true)
    const note = within(sommaire).getByText(
      'Votre abonnement est suspendu. Contactez COVI pour le renouveler.',
    )
    expect(add.getAttribute('aria-describedby')).toBe(note.id)
  })

  it('subscription unverified: one discreet line, the sale still open', () => {
    const { sommaire } = renderWith({ shopCount: 1, readOnly: false, subscriptionUnverified: true })
    const line = screen.getByText('État de l’abonnement non vérifié')
    expect(line.closest('.notice')).toBeNull()
    expect(screen.queryByText(READ_ONLY)).toBeNull()
    const sale = within(sommaire).getByText('Nouvelle vente').closest('a')!
    expect(sale.getAttribute('aria-disabled')).toBeNull()
    expect(sale.getAttribute('href')).not.toBeNull()
  })

  it('no banner while the subscription is fine', () => {
    renderWith({ shopCount: 1, readOnly: false })
    expect(screen.queryByText(READ_ONLY)).toBeNull()
  })

  it('read only: permanent calm banner, the sale entries disabled, the pages still readable', async () => {
    const { sommaire, bottom } = renderWith({ shopCount: 1, readOnly: true })
    const banner = screen.getByText(READ_ONLY)
    expect(banner.id).toBe('abonnement-suspendu')
    expect(banner.closest('.notice')?.className).not.toContain('notice--danger')
    // « Nouvelle vente » (Sommaire) and « Vendre » (bottom bar) are no longer links.
    const sale = within(sommaire).getByText('Nouvelle vente').closest('a')!
    expect(sale.getAttribute('aria-disabled')).toBe('true')
    expect(sale.getAttribute('href')).toBeNull()
    expect(sale.getAttribute('aria-describedby')).toBe('abonnement-suspendu')
    const sell = within(bottom).getByText('Vendre').closest('a')!
    expect(sell.getAttribute('aria-disabled')).toBe('true')
    expect(sell.getAttribute('href')).toBeNull()
    // Reading pages stay open, and the banner stays on each of them.
    await go('#/ventes')
    expect(screen.getByText('page:history')).toBeTruthy()
    expect(screen.getByText(READ_ONLY)).toBeTruthy()
  })
})
