import { describe, expect, it } from 'vitest'
import type { Product } from '../../lib/types'
import { filterCounts, filterStock, isLow, keptStockLabel, piecesInShop } from './stockFilters'

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

const stock = [
  product('a', 'Robe wax modèle A', { category: 'Robes', arrival_id: 'chn' }),
  product('b', 'Jean droit modèle B', { quantity_on_hand: 1, arrival_id: 'chn' }),
  product('c', 'Chemise lin modèle C', { quantity_on_hand: 2, brand: 'Lino' }),
  product('e', 'Veste en jean', { quantity_on_hand: 1, is_unique_piece: true, arrival_id: 'bal' }),
  product('x', 'Pagne exemple', { is_test: true, quantity_on_hand: 4 }),
]
const codes = new Map([
  ['chn', 'CHN-001'],
  ['bal', 'BAL-003'],
])
const ids = (rows: Product[]) => rows.map((p) => p.id)

describe('filterStock', () => {
  it('keeps everything without search nor filter', () => {
    expect(ids(filterStock(stock, {}))).toEqual(['a', 'b', 'c', 'e', 'x'])
  })

  it('searches every word, without accents, in name, brand, type and arrival code', () => {
    expect(ids(filterStock(stock, { query: 'JEAN' }))).toEqual(['b', 'e'])
    expect(ids(filterStock(stock, { query: 'lino' }))).toEqual(['c'])
    expect(ids(filterStock(stock, { query: 'robes' }))).toEqual(['a'])
    expect(ids(filterStock(stock, { query: 'bal-003', codes }))).toEqual(['e'])
    expect(ids(filterStock(stock, { query: 'modele jean' }))).toEqual(['b'])
  })

  it('« Bientôt épuisé » keeps models with 2 or fewer left, never unique pieces', () => {
    expect(ids(filterStock(stock, { filter: 'low' }))).toEqual(['b', 'c'])
    expect(isLow(stock[3])).toBe(false)
  })

  it('« Pièces uniques » and the arrival filter combine with the search', () => {
    expect(ids(filterStock(stock, { filter: 'unique' }))).toEqual(['e'])
    expect(ids(filterStock(stock, { arrival: 'chn' }))).toEqual(['a', 'b'])
    expect(ids(filterStock(stock, { arrival: 'none' }))).toEqual(['c', 'x'])
    expect(ids(filterStock(stock, { arrival: 'chn', filter: 'low', query: 'jean' }))).toEqual(['b'])
  })
})

describe('stock counts', () => {
  it('counts the pieces in the shop, examples excluded', () => {
    expect(piecesInShop(stock)).toBe(3 + 1 + 2 + 1)
  })

  it('counts what each filter shows', () => {
    expect(filterCounts(stock)).toEqual({ all: 5, low: 2, unique: 1 })
  })
})

describe('keptStockLabel', () => {
  const now = new Date(2026, 9, 8, 15, 10)
  it('dates the copy kept on the phone calmly', () => {
    expect(keptStockLabel(new Date(2026, 9, 8, 14, 32).toISOString(), now)).toBe(
      'Stock gardé sur ce téléphone · mis à jour à 14 h 32',
    )
    expect(keptStockLabel(new Date(2026, 9, 2, 9, 5).toISOString(), now)).toBe(
      'Stock gardé sur ce téléphone · mis à jour le 2 oct. à 9 h 05',
    )
    expect(keptStockLabel(null, now)).toBe('Stock gardé sur ce téléphone')
  })
})
