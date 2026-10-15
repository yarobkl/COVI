import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { adjustProductStock, setProductArchived, updateProductDetails } from '../../lib/stock'
import type { Product } from '../../lib/types'
import { ProductEditor } from './ProductEditor'

vi.mock('../../lib/stock', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../lib/stock')>()),
  adjustProductStock: vi.fn().mockResolvedValue({}),
  setProductArchived: vi.fn().mockResolvedValue({}),
  updateProductDetails: vi.fn().mockResolvedValue(null),
  listStockMovements: vi.fn().mockResolvedValue([]),
}))

afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

const robe: Product = {
  id: 'p1',
  shop_id: 'shop-1',
  arrival_id: null,
  name: 'Robe wax',
  category: 'Robes',
  brand: null,
  size: 'M',
  initial_sale_price: 15000,
  quantity_on_hand: 2,
  is_unique_piece: false,
  status: 'active',
  is_test: false,
  image_path: null,
  created_at: '2026-10-01T00:00:00Z',
  updated_at: '2026-10-01T00:00:00Z',
}

describe('ProductEditor', () => {
  it('restocks with a reason, never without one', async () => {
    const onChanged = vi.fn()
    render(<ProductEditor product={robe} onClose={() => {}} onChanged={onChanged} />)
    const save = () =>
      screen.getByRole('button', {
        name: /Changez la quantité|Choisissez un motif|Enregistrer la correction/,
      })
    expect((save() as HTMLButtonElement).disabled).toBe(true)
    fireEvent.click(screen.getByRole('button', { name: 'Une pièce de plus : Robe wax' }))
    expect(save().textContent).toBe('Choisissez un motif')
    expect((save() as HTMLButtonElement).disabled).toBe(true)
    fireEvent.click(screen.getByLabelText('Réassort'))
    fireEvent.change(screen.getByPlaceholderText('Ex. : carton du 15 octobre'), {
      target: { value: 'Carton' },
    })
    fireEvent.click(save())
    await waitFor(() =>
      expect(adjustProductStock).toHaveBeenCalledWith('p1', 3, 'restock', 'Carton'),
    )
    await waitFor(() => expect(onChanged).toHaveBeenCalledWith('Stock de Robe wax : 2 → 3.'))
  })

  it('saves the product card and archives the product', async () => {
    const onChanged = vi.fn()
    render(<ProductEditor product={robe} onClose={() => {}} onChanged={onChanged} />)
    fireEvent.change(screen.getByLabelText('Prix de vente'), { target: { value: '12 000' } })
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer la fiche' }))
    await waitFor(() =>
      expect(updateProductDetails).toHaveBeenCalledWith('p1', {
        name: 'Robe wax',
        category: 'Robes',
        brand: null,
        size: 'M',
        initial_sale_price: 12000,
      }),
    )
    fireEvent.click(screen.getByRole('button', { name: 'Retirer de la vente' }))
    await waitFor(() => expect(setProductArchived).toHaveBeenCalledWith('p1', true))
  })
})
