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
  it('propose une description quand aucun article ne peut être publié', async () => {
    vi.mocked(fetchCatalog).mockResolvedValue({ ...base })
    render(<PublicOrderPage token="test-token" channel="qr" />)
    expect(
      await screen.findByText(/La boutique n’a pas encore d’articles disponibles/),
    ).toBeTruthy()
    expect(screen.getByPlaceholderText('Ex. robe wax rouge vue dans votre statut')).toBeTruthy()
    expect(screen.queryByRole('combobox', { name: 'Article' })).toBeNull()
  })

  it('laisse choisir un article connu OU décrire un autre article', async () => {
    vi.mocked(fetchCatalog).mockResolvedValue({
      ...base,
      products: [
        {
          id: 'product-1',
          name: 'Chemise',
          category: 'Vêtements',
          brand: null,
          size: 'L',
          priceXaf: 10000,
          maxQuantity: 2,
        },
      ],
    })
    render(<PublicOrderPage token="test-token" channel="social" />)
    const select = await screen.findByRole('combobox', { name: 'Article' })
    expect(screen.getByRole('option', { name: /Chemise/ })).toBeTruthy()
    fireEvent.change(select, { target: { value: '__covi_other_article__' } })
    expect(screen.getByPlaceholderText('Ex. chemise vue sur WhatsApp ou TikTok')).toBeTruthy()
    fireEvent.change(select, { target: { value: 'product-1' } })
    await waitFor(() =>
      expect(screen.queryByPlaceholderText('Ex. chemise vue sur WhatsApp ou TikTok')).toBeNull(),
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
