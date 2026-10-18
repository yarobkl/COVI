import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Shop } from '../../lib/types'
import { SectorHomePage } from './SectorHomePage'

const setup = vi.hoisted(() => ({
  tables: 0,
  menuItems: 0,
  fails: false,
}))

vi.mock('../../lib/supabase', () => ({
  supabase: {
    from: vi.fn((table: string) => ({
      select: () => ({
        eq() {
          return this
        },
        then(resolve: (value: unknown) => void, reject?: (reason: unknown) => void) {
          const count = table === 'restaurant_tables' ? setup.tables : setup.menuItems
          return Promise.resolve({
            count: setup.fails ? null : count,
            error: setup.fails ? { message: 'Offline' } : null,
          }).then(resolve, reject)
        },
      }),
    })),
  },
}))

const shop: Shop = {
  id: 'restaurant-123',
  name: 'Chez macaron Food',
  city: 'Brazzaville',
  country: 'République du Congo',
  currency: 'XAF',
  business_kind: 'restaurant',
}

beforeEach(() => {
  setup.tables = 0
  setup.menuItems = 0
  setup.fails = false
})
afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

describe('SectorHomePage — comprendre la logique restaurant', () => {
  it('shows the real order of setup and what happens in a service', async () => {
    render(<SectorHomePage shop={shop} />)
    expect(await screen.findByText('Préparation : 0 étape sur 2 terminée')).toBeTruthy()
    expect(screen.getByRole('link', { name: 'Ajouter mes tables' }).getAttribute('href')).toBe(
      '#/restaurant-tables',
    )
    expect(screen.getByText('Organiser les tables')).toBeTruthy()
    expect(screen.getByText('Créer la carte')).toBeTruthy()
    expect(screen.getByText('Un client arrive. Ouvrez sa table.')).toBeTruthy()
    expect(screen.getByText('Enregistrez l’argent reçu en espèces.')).toBeTruthy()
    expect(screen.getByText(/La table se libère après le service et le règlement complet/)).toBeTruthy()
  })

  it('advances to the menu when real active tables exist', async () => {
    setup.tables = 3
    render(<SectorHomePage shop={shop} />)
    expect(await screen.findByText('Préparation : 1 étape sur 2 terminée')).toBeTruthy()
    expect(screen.getByText('3 table(s) active(s) enregistrée(s).')).toBeTruthy()
    expect(screen.getByRole('link', { name: 'Créer ma carte' }).getAttribute('href')).toBe(
      '#/restaurant-menu',
    )
  })

  it('moves to Service & caisse only after both parts are present', async () => {
    setup.tables = 2
    setup.menuItems = 5
    render(<SectorHomePage shop={shop} />)
    expect(await screen.findByText('Préparation : 2 étapes sur 2 terminées')).toBeTruthy()
    expect(screen.getByRole('link', { name: 'Ouvrir Service & caisse' }).getAttribute('href')).toBe(
      '#/restaurant-orders',
    )
    expect(screen.getByText('5 plat(s) ou boisson(s) disponible(s).')).toBeTruthy()
  })

  it('never mistakes failed database reads for an empty restaurant', async () => {
    setup.fails = true
    render(<SectorHomePage shop={shop} />)
    expect(await screen.findByText('Impossible de vérifier votre installation pour le moment.')).toBeTruthy()
    expect(screen.queryByText(/Préparation : 0 étape/)).toBeNull()
    expect(screen.getByRole('link', { name: 'Voir mes tables' }).getAttribute('href')).toBe(
      '#/restaurant-tables',
    )
  })

  it('retains the salon screen without reading restaurant data', () => {
    render(<SectorHomePage shop={{ ...shop, business_kind: 'salon' }} />)
    expect(screen.getByText('Bienvenue dans votre salon')).toBeTruthy()
    expect(screen.getByRole('link', { name: 'Mes prestations' })).toBeTruthy()
  })
})
