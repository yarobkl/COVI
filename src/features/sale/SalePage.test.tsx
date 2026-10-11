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

  /** Two articles in the cart, sheet open, paid by card. */
  async function twoArticlesInSheet() {
    render(<SalePage shopId="shop-1" shopName="Chez Mado" />)
    await screen.findByText('Robe wax')
    fireEvent.click(tile('Robe wax'))
    fireEvent.click(tile('Jean slim'))
    fireEvent.click(screen.getByRole('button', { name: /Voir le panier/ }))
    fireEvent.click(sheet().getByRole('radio', { name: 'Carte' }))
  }
  const opIds = () =>
    rpc.mock.calls.map((c) => (c[1] as { p_client_operation_id: string }).p_client_operation_id)
  const UNCERTAIN =
    'La connexion a coupé pendant l’envoi. On ne sait pas encore si la vente est passée. Réessayez : elle ne sera pas comptée deux fois.'

  it('no network before sending: nothing sent, the cart stays whole and editable', async () => {
    online = false
    await twoArticlesInSheet()
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    expect(
      await sheet().findByText(
        'Pas de réseau : ce panier attend. Il sera enregistré d’un coup dès que le réseau revient. Vous pouvez aussi vendre article par article.',
      ),
    ).toBeTruthy()
    expect(rpc).not.toHaveBeenCalled()
    expect(resilientSale).not.toHaveBeenCalled()
    expect(sheet().getAllByRole('button', { name: /^Retirer/ })).toHaveLength(2)
    fireEvent.click(sheet().getByRole('button', { name: 'Une pièce de plus : Robe wax' }))
    expect(sheet().getByText('Total (3 articles)')).toBeTruthy()
    fireEvent.click(sheet().getByRole('button', { name: 'Retirer Jean slim du panier' }))
    expect(sheet().getAllByRole('button', { name: /^Retirer/ })).toHaveLength(1)
  })

  it('network cut during the call: the cart freezes, « Réessayer » resends the very same call', async () => {
    await twoArticlesInSheet()
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'Failed to fetch', code: '' } })
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    expect(await sheet().findByText(UNCERTAIN)).toBeTruthy()

    // Nothing can change: no « Retirer », no quantity, no price key, no payment choice.
    expect(sheet().queryAllByRole('button', { name: /^Retirer/ })).toHaveLength(0)
    expect(sheet().queryByRole('button', { name: /Une pièce de plus/ })).toBeNull()
    expect(sheet().queryByRole('button', { name: /vendu à/ })).toBeNull()
    expect(sheet().queryByRole('radio')).toBeNull()
    expect(sheet().queryByRole('button', { name: /Ajouter un autre article/ })).toBeNull()
    expect(sheet().getByText('Payé par carte')).toBeTruthy()

    // The sheet closes and opens again: still frozen. A tile adds nothing, it shows the cart.
    fireEvent.click(sheet().getByRole('button', { name: 'Revenir aux articles' }))
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(screen.getByRole('button', { name: /Voir le panier/ }).textContent).toMatch(
      /Vente à confirmer · 2 articles/,
    )
    fireEvent.click(tile('Robe wax'))
    expect(sheet().getByText(UNCERTAIN)).toBeTruthy()
    expect(sheet().getByText('Total (2 articles)')).toBeTruthy()

    fireEvent.click(sheet().getByRole('button', { name: /^Réessayer/ }))
    expect(await screen.findByText('Vendu.')).toBeTruthy()
    expect(rpc).toHaveBeenCalledTimes(2)
    expect(rpc.mock.calls[1]).toEqual(rpc.mock.calls[0])
    expect(opIds()[1]).toBe(opIds()[0])
    expect(screen.getByText('Jean slim')).toBeTruthy()
    expect(screen.getByText('Robe wax')).toBeTruthy()

    // The next sale is a new, open cart with a new key.
    fireEvent.click(screen.getByRole('button', { name: 'Vente suivante' }))
    await screen.findByText('Robe wax')
    fireEvent.click(tile('Robe wax'))
    fireEvent.click(tile('Jean slim'))
    fireEvent.click(screen.getByRole('button', { name: /Voir le panier/ }))
    expect(sheet().getAllByRole('button', { name: /^Retirer/ })).toHaveLength(2)
    fireEvent.click(sheet().getByRole('radio', { name: 'Carte' }))
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    await waitFor(() => expect(rpc).toHaveBeenCalledTimes(3))
    expect(opIds()[2]).not.toBe(opIds()[0])
  })

  it('a frozen cart refused for good (SQLSTATE) becomes editable again', async () => {
    await twoArticlesInSheet()
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'Failed to fetch', code: '' } })
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    await sheet().findByText(UNCERTAIN)
    rpc.mockResolvedValueOnce({
      data: null,
      error: { message: 'Insufficient stock', code: 'P0001', details: 'item 0: available 1' },
    })
    fireEvent.click(sheet().getByRole('button', { name: /^Réessayer/ }))
    expect(
      await sheet().findByText('Robe wax : il n’en reste que 1. Baissez la quantité.'),
    ).toBeTruthy()
    expect(sheet().queryByText(UNCERTAIN)).toBeNull()
    expect(sheet().getAllByRole('button', { name: /^Retirer/ })).toHaveLength(2)
    expect((sheet().getByRole('radio', { name: 'Carte' }) as HTMLInputElement).checked).toBe(true)
  })

  it('« Abandonner ce panier » asks first, warns, then empties the cart', async () => {
    await twoArticlesInSheet()
    rpc.mockResolvedValueOnce({ data: null, error: { message: 'Failed to fetch', code: '' } })
    fireEvent.click(sheet().getByRole('button', { name: /Valider la vente/ }))
    await sheet().findByText(UNCERTAIN)

    fireEvent.click(sheet().getByRole('button', { name: 'Abandonner ce panier' }))
    const confirm = within(screen.getByRole('dialog', { name: 'Abandonner ce panier ?' }))
    expect(
      confirm.getByText(
        'La vente a peut-être déjà été enregistrée. Avant de revendre ces articles, vérifiez dans Ventes.',
      ),
    ).toBeTruthy()
    expect(confirm.getByRole('link', { name: 'Voir les ventes' }).getAttribute('href')).toBe(
      '#/ventes',
    )
    fireEvent.click(confirm.getByRole('button', { name: 'Garder le panier' }))
    expect(screen.queryByRole('dialog', { name: 'Abandonner ce panier ?' })).toBeNull()
    expect(sheet().getByText(UNCERTAIN)).toBeTruthy()

    fireEvent.click(sheet().getByRole('button', { name: 'Abandonner ce panier' }))
    fireEvent.click(
      within(screen.getByRole('dialog', { name: 'Abandonner ce panier ?' })).getByRole('button', {
        name: 'Abandonner',
      }),
    )
    expect(screen.queryByText(UNCERTAIN)).toBeNull()
    expect(screen.queryByRole('button', { name: /Voir le panier/ })).toBeNull()
    expect(rpc).toHaveBeenCalledTimes(1)
    // Tiles fill a new cart again.
    fireEvent.click(tile('Robe wax'))
    expect(screen.getByRole('button', { name: /Voir le panier/ }).textContent).toMatch(
      /Panier · 1 article/,
    )
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
