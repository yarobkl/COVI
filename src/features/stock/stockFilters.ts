// Stock list arithmetic, kept apart from the components to be tested: what is shown for a search
// and a filter, and how many pieces are in the shop.
import type { Product } from '../../lib/types'
import { matchesSearch } from '../sale/saleMath'

/** « Tout · Bientôt épuisé · Pièces uniques ». */
export type StockFilter = 'all' | 'low' | 'unique'

/** A model (not a unique piece) with 2 or fewer left: « Plus que 1 ». */
export const isLow = (p: Pick<Product, 'quantity_on_hand' | 'is_unique_piece'>) =>
  !p.is_unique_piece && p.quantity_on_hand > 0 && p.quantity_on_hand <= 2

/**
 * Products matching the words typed (name, brand, type, size or arrival code), the filter and
 * the arrival chosen (`''` = every arrival, `'none'` = articles without arrival).
 */
export function filterStock(
  products: readonly Product[],
  {
    query = '',
    filter = 'all',
    arrival = '',
    codes = new Map<string, string>(),
  }: {
    query?: string
    filter?: StockFilter
    arrival?: string
    codes?: ReadonlyMap<string, string>
  },
) {
  return products.filter((p) => {
    if (filter === 'low' && !isLow(p)) return false
    if (filter === 'unique' && !p.is_unique_piece) return false
    if (arrival === 'none' && p.arrival_id) return false
    if (arrival && arrival !== 'none' && p.arrival_id !== arrival) return false
    return matchesSearch(p, p.arrival_id ? codes.get(p.arrival_id) : undefined, query)
  })
}

/** Pieces in the shop (« 34 pièces en boutique »): every quantity left, examples excluded. */
export const piecesInShop = (products: readonly Product[]) =>
  products.reduce((n, p) => n + (p.is_test ? 0 : Math.max(0, Number(p.quantity_on_hand))), 0)

/** How many products each filter would show, for the chips (« Bientôt épuisé (2) »). */
export const filterCounts = (products: readonly Product[]) => ({
  all: products.length,
  low: products.filter(isLow).length,
  unique: products.filter((p) => p.is_unique_piece).length,
})
