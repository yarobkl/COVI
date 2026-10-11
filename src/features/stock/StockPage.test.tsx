import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { WriteLockContext } from '../../components/ui'
import { addProduct, listProducts } from '../../lib/covi'
import { listArrivals } from '../../lib/operations'
import type { Arrival, Product } from '../../lib/types'
import { StockPage } from './StockPage'

vi.mock('../../lib/covi', () => ({ addProduct: vi.fn(), listProducts: vi.fn() }))
vi.mock('../../lib/operations', () => ({ listArrivals: vi.fn() }))
vi.mock('../../lib/offline', () => ({ stockCacheDate: () => '2026-10-08T13:32:00.000Z' }))

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

const bal = { id: 'bal', code: 'BAL-003', kind: 'balloon', status: 'received' } as Arrival

beforeEach(() => {
  vi.mocked(listArrivals).mockResolvedValue([bal])
  vi.mocked(listProducts).mockResolvedValue([
    product('p1', 'Robe wax', { category: 'Robes' }),
    product('p2', 'Jean slim', { brand: 'Levi’s', quantity_on_hand: 1 }),
    product('p3', 'Veste vintage', {
      is_unique_piece: true,
      quantity_on_hand: 1,
      arrival_id: 'bal',
    }),
  ])
})
afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
})

const names = () =>
  within(screen.getByRole('list'))
    .queryAllByRole('listitem')
    .map((li) => li.querySelector('.stock-row__name')?.textContent)

describe('StockPage', () => {
  it('read only (subscription suspended): stock readable, « Ajouter au stock » disabled', async () => {
    render(
      <WriteLockContext.Provider value={{ reasonId: 'abonnement-suspendu', reason: 'Suspendu' }}>
        <StockPage shopId="shop-1" />
      </WriteLockContext.Provider>,
    )
    expect(await screen.findByText('Robe wax')).toBeTruthy()
    const add = screen.getByRole('button', { name: 'Ajouter au stock' }) as HTMLButtonElement
    expect(add.disabled).toBe(true)
    fireEvent.click(add)
    expect(addProduct).not.toHaveBeenCalled()
    expect(screen.queryByRole('dialog')).toBeNull()
  })

  it('counts the pieces and writes what is left on each line', async () => {
    render(<StockPage shopId="shop-1" />)
    expect(await screen.findByText('Robe wax')).toBeTruthy()
    expect(document.querySelector('.stock-head__count')?.textContent).toMatch(
      /^5\s+pièces\s+en\s+boutique$/,
    )
    expect(screen.getByText(/^Restent 3/)).toBeTruthy()
    expect(screen.getByText('Plus que 1').tagName).toBe('MARK')
    expect(screen.getByText(/^Pièce unique/)).toBeTruthy()
    expect(screen.getByText('BAL-003')).toBeTruthy()
  })

  it('searches and filters the loaded stock locally', async () => {
    render(<StockPage shopId="shop-1" />)
    await screen.findByText('Robe wax')
    const search = screen.getByLabelText('Chercher un article')
    fireEvent.change(search, { target: { value: 'LEVI' } })
    expect(names()).toEqual(['Jean slim'])
    fireEvent.change(search, { target: { value: 'pull' } })
    expect(screen.getByText('Rien ne correspond à « pull ». Vérifiez l’orthographe.')).toBeTruthy()
    fireEvent.change(search, { target: { value: '' } })
    fireEvent.click(screen.getByLabelText(/Bientôt épuisé/))
    expect(names()).toEqual(['Jean slim'])
    fireEvent.click(screen.getByLabelText(/Pièces uniques/))
    expect(names()).toEqual(['Veste vintage'])
    fireEvent.click(screen.getByLabelText(/Tout/))
    fireEvent.change(screen.getByLabelText('Arrivage'), { target: { value: 'bal' } })
    expect(names()).toEqual(['Veste vintage'])
    expect(listProducts).toHaveBeenCalledTimes(1)
  })

  it('says calmly that the stock is the copy kept on the phone', async () => {
    vi.spyOn(navigator, 'onLine', 'get').mockReturnValue(false)
    render(<StockPage shopId="shop-1" />)
    expect(await screen.findByText(/^Stock gardé sur ce téléphone · mis à jour/)).toBeTruthy()
  })

  it('guides an empty shop and offers to retry a failed load', async () => {
    vi.mocked(listProducts).mockResolvedValueOnce([])
    render(<StockPage shopId="shop-1" />)
    expect(await screen.findByText('Pas encore de produits.')).toBeTruthy()
    expect(
      screen.getByText('Ajoutez votre premier article ou enregistrez un arrivage.'),
    ).toBeTruthy()
    cleanup()
    vi.mocked(listProducts).mockRejectedValueOnce(new Error('Failed to fetch'))
    render(<StockPage shopId="shop-1" />)
    expect(await screen.findByText('Le stock ne s’affiche pas : pas de réseau.')).toBeTruthy()
    fireEvent.click(screen.getByText('Réessayer'))
    expect(await screen.findByText('Robe wax')).toBeTruthy()
  })

  it('adds an article from the sheet and says it is in stock', async () => {
    vi.mocked(addProduct).mockResolvedValue(product('p9', 'Chemise lin'))
    render(<StockPage shopId="shop-1" />)
    await screen.findByText('Robe wax')
    fireEvent.click(screen.getAllByText('Ajouter au stock')[0])
    fireEvent.click(await screen.findByText('Mettre en stock'))
    expect(await screen.findByText('Indiquez le nom de l’article.')).toBeTruthy()
    expect(addProduct).not.toHaveBeenCalled()
    fireEvent.change(screen.getByLabelText('Nom de l’article'), {
      target: { value: 'Chemise lin' },
    })
    fireEvent.change(screen.getByLabelText('Prix affiché (FCFA)'), { target: { value: '12000' } })
    fireEvent.change(screen.getByLabelText('Combien de pièces ?'), { target: { value: '6' } })
    fireEvent.click(screen.getByText('Mettre en stock'))
    await waitFor(() => expect(addProduct).toHaveBeenCalled())
    expect(vi.mocked(addProduct).mock.calls[0]).toEqual([
      'shop-1',
      expect.objectContaining({
        name: 'Chemise lin',
        initial_sale_price: 12000,
        quantity_on_hand: 6,
        is_unique_piece: false,
        arrival_id: null,
      }),
    ])
    expect(await screen.findByText('Chemise lin est en stock.')).toBeTruthy()
  })
})
