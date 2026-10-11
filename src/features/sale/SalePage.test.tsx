import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { WriteLockContext } from '../../components/ui'
import { listProducts } from '../../lib/covi'
import { resilientSale } from '../../lib/offline'
import { listArrivals, todaySales } from '../../lib/operations'
import { supabase } from '../../lib/supabase'
import type { Product } from '../../lib/types'
import { SalePage } from './SalePage'

vi.mock('../../lib/covi', () => ({ listProducts: vi.fn() }))
vi.mock('../../lib/operations', () => ({ listArrivals: vi.fn(), todaySales: vi.fn() }))
vi.mock('../../lib/offline', () => ({ resilientSale: vi.fn() }))
vi.mock('../../lib/supabase', () => ({
  supabase: { auth: { getSession: vi.fn() }, rpc: vi.fn() },
}))

const product = (id: string, name: string, extra: Partial<Product> = {}): Product => ({
  id,
  shop_id: 'shop-1',
  arrival_id: null,
  name,
  category: null,
  brand: null,
  size: null,
  initial_sale_price: 10000,
  quantity_on_hand: 3,
  is_unique_piece: false,
  status: 'active',
  is_test: false,
  image_path: null,
  created_at: '2026-10-01T00:00:00Z',
  updated_at: '2026-10-01T00:00:00Z',
  ...extra,
})

const ROBE = '11111111-1111-4111-8111-111111111111'
const JEAN = '22222222-2222-4222-8222-222222222222'
const rpc = vi.mocked(supabase.rpc) as unknown as ReturnType<typeof vi.fn>
let online = true

beforeEach(() => {
  online = true
  Object.defineProperty(navigator, 'onLine', { configurable: true, get: () => online })
  vi.mocked(listProducts).mockResolvedValue([
    product(ROBE, 'Robe wax'),
    product(JEAN, 'Jean slim', { initial_sale_price: 15000, quantity_on_hand: 1 }),
  ])
  vi.mocked(listArrivals).mockResolvedValue([])
  vi.mocked(todaySales).mockResolvedValue({ count: 4, total: 100000 } as never)
  vi.mocked(supabase.auth.getSession).mockResolvedValue({
    data: { session: { access_token: 't' } },
    error: null,
  } as never)
  rpc.mockResolvedValue({ data: 'sale-1', error: null })
  vi.mocked(resilientSale).mockResolvedValue({ offline: false })
})
afterEach(() => {
  cleanup()
  vi.clearAllMocks()
  // @ts-expect-error -- restore jsdom (no matchMedia) after the computer tests.
  delete window.matchMedia
})

const tile = (name: string) => screen.getByRole('button', { name: new RegExp(`^Ajouter ${name}`) })
const sheet = () => within(screen.getByRole('dialog'))

describe('SalePage — the cart (phone)', () => {
  it('fills the cart, changes a quantity and a price, validates once, lists both articles', async () => {
    render(<SalePage shopId="shop-1" shopName="Chez Mado" />)
    await screen.findByText('Robe wax')
    expect(screen.queryByRole('button', { name: /Voir le panier/ })).toBeNull()

    fireEvent.click(tile('Robe wax'))
    fireEvent.click(tile('Jean slim'))
    expect(screen.getByRole('status', { name: '' }).textContent).toBe(
      'Ajouté au panier : Jean slim.',
    )
    expect(tile('Robe wax').getAttribute('aria-label')).toContain('déjà 1 dans le panier')
    const bar = screen.getByRole('button', { name: /Voir le panier/ })
    expect(bar.textContent).toMatch(/Panier · 2 articles\s*25\s000/)

    fireEvent.click(bar)
    fireEvent.click(sheet().getByRole('button', { name: 'Une pièce de plus : Robe wax' }))
    fireEvent.click(sheet().getByRole('button', { name: /^Jean slim vendu à/ }))
    fireEvent.click(sheet().getByRole('button', { name: 'Baisser de 1 000 FCFA' }))
    fireEvent.click(sheet().getByRole('button', { name: 'Garder ce prix' }))
    expect(sheet().getByText('Total (3 articles)')).toBeTruthy()
    fireEvent.click(sheet().getByRole('radio', { name: 'Mobile Money' }))
    const validate = sheet().getByRole('button', { name: /Valider la vente/ })
    expect(validate.textContent).toMatch(/34\s000/)
    fireEvent.click(validate)

    expect(await screen.findByText('Vendu.')).toBeTruthy()
    expect(rpc).toHaveBeenCalledTimes(1)
    expect(rpc.mock.calls[0][0]).toBe('record_cart_sale')
    expect(rpc.mock.calls[0][1]).toMatchObject({
      p_shop_id: 'shop-1',
      p_items: [
        { product_id: ROBE, quantity: 2, sold_unit_price: 10000 },
        { product_id: JEAN, quantity: 1, sold_unit_price: 14000 },
      ],
      p_payment_method: 'mobile_money',
    })
    expect(resilientSale).not.toHaveBeenCalled()
    expect(screen.getByText('2 × Robe wax')).toBeTruthy()
    expect(screen.getByText('Jean slim')).toBeTruthy()
    expect(screen.getByText('3 articles dans cette vente')).toBeTruthy()
    expect(document.querySelector('.sale-done__day')?.textContent).toMatch(
      /^5e vente aujourd’hui · 134\s000\sFCFA$/,
    )

    // « Vente suivante »: an empty cart.
    fireEvent.click(screen.getByRole('button', { name: 'Vente suivante' }))
    expect(await screen.findByText('Aujourd’hui : 5 ventes ·', { exact: false })).toBeTruthy()
    expect(screen.queryByRole('button', { name: /Voir le panier/ })).toBeNull()
  })

  it('keeps a unique stock bound, and « Retirer » empties the line', async () => {
    render(<SalePage shopId="shop-1" shopName="Chez Mado" />)
    await screen.findByText('Jean slim')
    fireEvent.click(tile('Jean slim'))
    fireEvent.click(tile('Jean slim'))
    expect(screen.getByRole('status', { name: '' }).textContent).toBe(
      'Tout le stock de Jean slim est déjà dans le panier.',
    )
    fireEvent.click(screen.getByRole('button', { name: /Voir le panier/ }))
    expect(sheet().getByText('1 pièce')).toBeTruthy()
    fireEvent.click(sheet().getByRole('button', { name: 'Retirer Jean slim du panier' }))
    expect(sheet().getByText('Le panier est vide. Touchez un article pour l’ajouter.')).toBeTruthy()
  })

  it('one article sells as before, through resilientSale', async () => {
    render(<SalePage shopId="shop-1" shopName="Chez Mado" />)
    await screen.findByText('Robe wax')
    fireEvent.click(tile('Robe wax'))
    fireEvent.click(screen.getByRole('button', { name: /Voir le panier/ }))
    fireEvent.click(sheet().getByRole('radio', { name: 'Espèces' }))
    fireEvent.click(sheet().getByRole('button', { name: 'Compte juste' }))
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    expect(await screen.findByText('Vendu.')).toBeTruthy()
    expect(resilientSale).toHaveBeenCalledWith({
      shopId: 'shop-1',
      productId: ROBE,
      quantity: 1,
      soldUnitPrice: 10000,
      paymentLabel: 'Espèces',
    })
    expect(rpc).not.toHaveBeenCalled()
    expect(screen.getByText('Robe wax · il en reste 2')).toBeTruthy()
  })

  it('without network, a cart of two articles waits on screen, intact, and is retried with the same key', async () => {
    online = false
    render(<SalePage shopId="shop-1" shopName="Chez Mado" />)
    await screen.findByText('Robe wax')
    fireEvent.click(tile('Robe wax'))
    fireEvent.click(tile('Jean slim'))
    fireEvent.click(screen.getByRole('button', { name: /Voir le panier/ }))
    fireEvent.click(sheet().getByRole('radio', { name: 'Carte' }))
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    expect(
      await sheet().findByText(
        'Pas de réseau : ce panier attend. Il sera enregistré d’un coup dès que le réseau revient. Vous pouvez aussi vendre article par article.',
      ),
    ).toBeTruthy()
    expect(rpc).not.toHaveBeenCalled()
    expect(resilientSale).not.toHaveBeenCalled()
    expect(sheet().getAllByRole('button', { name: /^Retirer/ })).toHaveLength(2)

    // The network drops during the call, then comes back: the same operation id both times.
    online = true
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'Failed to fetch', code: '' } })
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    await waitFor(() => expect(rpc).toHaveBeenCalledTimes(1))
    await sheet().findByText(/ce panier attend/)
    // The seller closes the sheet and comes back to the same cart: still the same key.
    fireEvent.click(sheet().getByRole('button', { name: 'Revenir aux articles' }))
    expect(screen.queryByRole('dialog')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: /Voir le panier/ }))
    fireEvent.click(sheet().getByRole('radio', { name: 'Carte' }))
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    expect(await screen.findByText('Vendu.')).toBeTruthy()
    const ids = rpc.mock.calls.map(
      (c) => (c[1] as { p_client_operation_id: string }).p_client_operation_id,
    )
    expect(ids).toHaveLength(2)
    expect(ids[1]).toBe(ids[0])
  })

  it('a refusal keeps the cart and says which article', async () => {
    rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'Product unavailable', code: 'P0001', details: 'item 1: …' },
    })
    render(<SalePage shopId="shop-1" shopName="Chez Mado" />)
    await screen.findByText('Robe wax')
    fireEvent.click(tile('Robe wax'))
    fireEvent.click(tile('Jean slim'))
    fireEvent.click(screen.getByRole('button', { name: /Voir le panier/ }))
    fireEvent.click(sheet().getByRole('radio', { name: 'Autre' }))
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    expect(
      await sheet().findByText(
        'Jean slim : cet article n’est plus en stock. Il a peut-être déjà été vendu.',
      ),
    ).toBeTruthy()
    expect(screen.queryByText('Vendu.')).toBeNull()
  })
})

describe('SalePage — computer', () => {
  beforeEach(() => {
    window.matchMedia = ((query: string) => ({
      matches: true,
      media: query,
      addEventListener: () => {},
      removeEventListener: () => {},
    })) as unknown as typeof window.matchMedia
  })

  it('the cart sits beside the articles', async () => {
    render(<SalePage shopId="shop-1" shopName="Chez Mado" />)
    await screen.findByText('Robe wax')
    const aside = within(screen.getByRole('complementary', { name: 'La vente' }))
    expect(aside.getByText('Le panier est vide. Touchez un article pour l’ajouter.')).toBeTruthy()
    fireEvent.click(tile('Robe wax'))
    fireEvent.click(tile('Robe wax'))
    expect(aside.getByRole('list', { name: 'Le panier' })).toBeTruthy()
    expect(aside.getByText('Total (2 × 10 000)')).toBeTruthy()
    expect(screen.queryByRole('button', { name: /Voir le panier/ })).toBeNull()
  })
})

describe('SalePage — read only', () => {
  it('tiles and validation stay closed, the stock stays readable', async () => {
    render(
      <WriteLockContext.Provider value={{ reasonId: 'abonnement-suspendu', reason: 'Suspendu' }}>
        <SalePage shopId="shop-1" shopName="Chez Mado" />
      </WriteLockContext.Provider>,
    )
    await screen.findByText('Robe wax')
    const robe = tile('Robe wax') as HTMLButtonElement
    expect(robe.disabled).toBe(true)
    expect(robe.getAttribute('aria-describedby')).toBe('abonnement-suspendu')
    fireEvent.click(robe)
    expect(screen.queryByRole('button', { name: /Voir le panier/ })).toBeNull()
    expect(rpc).not.toHaveBeenCalled()
    expect(resilientSale).not.toHaveBeenCalled()
  })
})
