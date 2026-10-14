import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fetchCatalog, type PublicCatalog } from '../../lib/publicOrders'
import { PublicOrderPage } from './PublicOrderPage'

vi.mock('../../lib/publicOrders', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../lib/publicOrders')>()),
  fetchCatalog: vi.fn(),
}))
vi.mock('./TurnstileChallenge', () => ({
  TurnstileChallenge: () => <span>Vérification anti-robot</span>,
}))

const base: PublicCatalog = {
  shopName: 'YARO BOUTIQUE',
  city: 'Brazzaville',
  neighborhood: null,
  message: null,
  showCatalog: true,
  products: [],
  ordersOpen: true,
}

beforeEach(() => {
  vi.mocked(fetchCatalog).mockReset()
})
afterEach(() => cleanup())

describe('QR client — liste des articles et description de remplacement', () => {
  it('propose les types d’articles même sans stock disponible', async () => {
    vi.mocked(fetchCatalog).mockResolvedValue({ ...base })
    render(<PublicOrderPage token="test-token" channel="qr" />)
    await screen.findByRole('combobox', { name: 'Choisir un article' })
    expect(screen.getByRole('option', { name: 'Pantalon' })).toBeTruthy()
    expect(screen.getByRole('option', { name: 'Autre article' })).toBeTruthy()
  })

  it('laisse choisir un type de la boutique OU décrire un autre article', async () => {
    vi.mocked(fetchCatalog).mockResolvedValue({ ...base, articleTypes: ['Chemise', 'Robe'] })
    render(<PublicOrderPage token="test-token" channel="social" />)
    const select = await screen.findByRole('combobox', { name: 'Choisir un article' })
    expect(screen.getByRole('option', { name: 'Chemise' })).toBeTruthy()
    expect(screen.queryByRole('option', { name: 'Pantalon' })).toBeNull()
    fireEvent.change(select, { target: { value: '__covi_other_article__' } })
    expect(screen.getByPlaceholderText('Ex. tenue traditionnelle pour enfant')).toBeTruthy()
    fireEvent.change(select, { target: { value: 'Chemise' } })
    await waitFor(() =>
      expect(screen.getByPlaceholderText('Ex. taille L, bleu, vu sur WhatsApp')).toBeTruthy(),
    )
  })

  it('propose aussi une description lorsque la boutique masque volontairement son catalogue', async () => {
    vi.mocked(fetchCatalog).mockResolvedValue({
      ...base,
      showCatalog: false,
      products: [],
    })
    render(<PublicOrderPage token="test-token" channel="qr" />)
    expect(
      await screen.findByPlaceholderText('Ex. robe wax rouge vue dans votre statut'),
    ).toBeTruthy()
    expect(screen.queryByText(/La boutique n’a pas encore d’articles disponibles/)).toBeNull()
  })
})
