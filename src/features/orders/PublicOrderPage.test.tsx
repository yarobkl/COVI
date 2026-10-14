import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { compressReferencePhoto, fetchCatalog, type PublicCatalog } from '../../lib/publicOrders'
import { PublicOrderPage } from './PublicOrderPage'

vi.mock('../../lib/publicOrders', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../lib/publicOrders')>()),
  fetchCatalog: vi.fn(),
  compressReferencePhoto: vi.fn(),
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
  articleTypes: ['Pantalon', 'Chemise', 'Robe'],
  products: [],
  ordersOpen: true,
}

beforeEach(() => {
  vi.mocked(fetchCatalog).mockReset()
  vi.mocked(compressReferencePhoto).mockReset()
})
afterEach(() => cleanup())

describe('QR client — types vendus, indépendamment des références et du stock', () => {
  it('affiche pantalon et chemise même quand le stock public est vide', async () => {
    vi.mocked(fetchCatalog).mockResolvedValue({ ...base })
    render(<PublicOrderPage token="test-token" channel="qr" />)
    const select = await screen.findByRole('combobox', { name: 'Choisir un article' })
    expect(screen.getByRole('option', { name: 'Pantalon' })).toBeTruthy()
    expect(screen.getByRole('option', { name: 'Chemise' })).toBeTruthy()
    fireEvent.change(select, { target: { value: 'Pantalon' } })
    expect((select as HTMLSelectElement).value).toBe('Pantalon')
    expect(screen.getByPlaceholderText('Ex. taille L, bleu, vu sur WhatsApp')).toBeTruthy()
  })

  it('respecte la liste personnalisée de la boutique, pas les produits en stock', async () => {
    vi.mocked(fetchCatalog).mockResolvedValue({
      ...base,
      articleTypes: ['Boubou', 'Pagne'],
      products: [
        {
          id: 'sku-1',
          name: 'Chaussure unique',
          category: 'Chaussures',
          brand: null,
          size: null,
          priceXaf: 12000,
          maxQuantity: 1,
        },
      ],
    })
    render(<PublicOrderPage token="test-token" channel="social" />)
    const select = await screen.findByRole('combobox', { name: 'Choisir un article' })
    expect(screen.getByRole('option', { name: 'Boubou' })).toBeTruthy()
    expect(screen.getByRole('option', { name: 'Pagne' })).toBeTruthy()
    expect(screen.queryByRole('option', { name: /Chaussure unique/ })).toBeNull()
    fireEvent.change(select, { target: { value: '__covi_other_article__' } })
    expect(screen.getByPlaceholderText('Ex. tenue traditionnelle pour enfant')).toBeTruthy()
    fireEvent.change(select, { target: { value: 'Pagne' } })
    await waitFor(() =>
      expect(screen.queryByPlaceholderText('Ex. tenue traditionnelle pour enfant')).toBeNull(),
    )
  })

  it('propose une description quand la boutique désactive son catalogue', async () => {
    vi.mocked(fetchCatalog).mockResolvedValue({
      ...base,
      showCatalog: false,
    })
    render(<PublicOrderPage token="test-token" channel="qr" />)
    expect(
      await screen.findByPlaceholderText('Ex. robe wax rouge vue dans votre statut'),
    ).toBeTruthy()
    expect(screen.queryByRole('combobox', { name: 'Choisir un article' })).toBeNull()
  })
  it('permet de joindre une capture du modèle juste après les articles et de la retirer', async () => {
    vi.mocked(fetchCatalog).mockResolvedValue({ ...base })
    vi.mocked(compressReferencePhoto).mockResolvedValue('data:image/jpeg;base64,/9j/2Q==')
    render(<PublicOrderPage token="test-token" channel="qr" />)
    await screen.findByRole('combobox', { name: 'Choisir un article' })
    const upload = screen.getByLabelText('Ajouter une capture d’écran ou une photo du modèle')
    const section = screen.getByRole('region', { name: 'Photo du modèle recherché' })
    expect(section.contains(upload)).toBe(true)
    const file = new File(['fake image'], 'capture-whatsapp.png', { type: 'image/png' })
    fireEvent.change(upload, { target: { files: [file] } })
    await waitFor(() => expect(compressReferencePhoto).toHaveBeenCalledWith(file))
    expect(await screen.findByAltText('Aperçu de la photo du modèle à commander')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Retirer la photo' }))
    expect(screen.queryByAltText('Aperçu de la photo du modèle à commander')).toBeNull()
  })

})
