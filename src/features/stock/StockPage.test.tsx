import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { listProducts } from '../../lib/covi'
import type { Product } from '../../lib/types'
import { StockPage } from './StockPage'

vi.mock('../../lib/covi', () => ({ addProduct: vi.fn(), listProducts: vi.fn() }))
vi.mock('../../lib/operations', () => ({ listArrivals: vi.fn().mockResolvedValue([]) }))
vi.mock('../../lib/offline', () => ({ stockCacheDate: () => null }))

afterEach(cleanup)

const product = (id: string, name: string, extra: Partial<Product> = {}): Product => ({
  id,
  shop_id: 'shop-1',
  arrival_id: null,
  name,
  category: null,
  brand: null,
  size: null,
  initial_sale_price: 10000,
  quantity_on_hand: 2,
  is_unique_piece: false,
  status: 'active',
  is_test: false,
  image_path: null,
  created_at: '2026-10-01T00:00:00Z',
  updated_at: '2026-10-01T00:00:00Z',
  ...extra,
})

describe('StockPage search', () => {
  it('filters the loaded stock locally on name, brand and category', async () => {
    vi.mocked(listProducts).mockResolvedValue([
      product('p1', 'Robe wax', { category: 'Robes' }),
      product('p2', 'Jean slim', { brand: 'Levi’s' }),
      product('p3', 'Veste vintage', { is_unique_piece: true, quantity_on_hand: 1 }),
    ])
    render(<StockPage shopId="shop-1" />)
    expect(await screen.findByText('Robe wax')).toBeTruthy()
    expect(screen.getByText('1 pièce')).toBeTruthy()
    const search = screen.getByPlaceholderText('Rechercher…')
    fireEvent.change(search, { target: { value: 'LEVI' } })
    expect(screen.queryByText('Robe wax')).toBeNull()
    expect(screen.getByText('Jean slim')).toBeTruthy()
    fireEvent.change(search, { target: { value: 'robes' } })
    expect(screen.getByText('Robe wax')).toBeTruthy()
    expect(screen.queryByText('Jean slim')).toBeNull()
    fireEvent.change(search, { target: { value: '' } })
    expect(screen.getByText('Veste vintage')).toBeTruthy()
    expect(listProducts).toHaveBeenCalledTimes(1)
  })
})
