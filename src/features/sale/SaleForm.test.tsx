import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { recordTillSale } from '../../lib/covi'
import { resilientSale } from '../../lib/offline'
import type { Product } from '../../lib/types'
import { SaleForm } from './SaleForm'

vi.mock('../../lib/covi', () => ({ recordTillSale: vi.fn() }))
vi.mock('../../lib/offline', () => ({ resilientSale: vi.fn() }))

const product = {
  id: 'p-1',
  shop_id: 'shop-1',
  name: 'Jean bleu',
  initial_sale_price: 10000,
  quantity_on_hand: 5,
  is_unique_piece: false,
  status: 'active',
} as unknown as Product

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

/** Types a price on the price pad (opened by the price key). */
function setPrice(price: string) {
  fireEvent.click(screen.getByRole('button', { name: /Changer le prix/ }))
  for (let i = 0; i < 6; i++)
    fireEvent.click(screen.getByRole('button', { name: 'Effacer un chiffre' }))
  for (const d of price) fireEvent.click(screen.getByRole('button', { name: d }))
  fireEvent.click(screen.getByRole('button', { name: 'Garder ce prix' }))
}

describe('SaleForm with a cashier (maximum discount)', () => {
  it('blocks a price under the minimum and says it in the shop’s words', () => {
    render(
      <SaleForm
        shopId="shop-1"
        product={product}
        keyboard={false}
        onSold={vi.fn()}
        seller={{ name: 'Awa', maxDiscountPct: 10 }}
      />,
    )
    setPrice('8000')
    expect(
      screen.getByText(
        /^Ce prix est en dessous du minimum autorisé \(9.000 FCFA\)\. Demandez au responsable\.$/,
      ),
    ).toBeTruthy()
    const validate = screen.getByRole('button', { name: 'Prix sous le minimum autorisé' })
    expect((validate as HTMLButtonElement).disabled).toBe(true)
  })

  it('accepts the minimum and sells through the offline-capable path (own account)', async () => {
    vi.mocked(resilientSale).mockResolvedValue({ offline: false })
    const onSold = vi.fn()
    render(
      <SaleForm
        shopId="shop-1"
        product={product}
        keyboard={false}
        onSold={onSold}
        seller={{ name: 'Awa', maxDiscountPct: 10 }}
      />,
    )
    setPrice('9000')
    fireEvent.click(screen.getByRole('radio', { name: /Espèces/ }))
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /Valider la vente/ }))
    })
    expect(resilientSale).toHaveBeenCalledWith(expect.objectContaining({ soldUnitPrice: 9000 }))
    expect(onSold).toHaveBeenCalled()
  })

  it('sells in the name of the till session cashier, online only', async () => {
    vi.mocked(recordTillSale).mockResolvedValue('sale-1')
    render(
      <SaleForm
        shopId="shop-1"
        product={product}
        keyboard={false}
        onSold={vi.fn()}
        seller={{ name: 'Awa', maxDiscountPct: 10, tillToken: 't'.repeat(64) }}
      />,
    )
    fireEvent.click(screen.getByRole('radio', { name: /Espèces/ }))
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: /Valider la vente/ }))
    })
    expect(recordTillSale).toHaveBeenCalledWith(
      'shop-1',
      'p-1',
      1,
      10000,
      'Espèces',
      't'.repeat(64),
      expect.any(String),
    )
    expect(resilientSale).not.toHaveBeenCalled()
  })

  it('the owner selling in their own name has no minimum', () => {
    render(<SaleForm shopId="shop-1" product={product} keyboard={false} onSold={vi.fn()} />)
    setPrice('1000')
    expect(screen.queryByText(/minimum autorisé/)).toBeNull()
  })
})
