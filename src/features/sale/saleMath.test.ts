import { describe, expect, it } from 'vitest'
import type { Product } from '../../lib/types'
import {
  cashChange,
  cashSuggestions,
  discountOf,
  isFarBelow,
  matchesSearch,
  normalize,
  stockNote,
} from './saleMath'

describe('discountOf', () => {
  it('is the difference with the displayed price, for the whole quantity', () => {
    expect(discountOf(15000, 13000)).toBe(2000)
    expect(discountOf(18000, 16000, 2)).toBe(4000)
    expect(discountOf(18000, 18000)).toBe(0)
    expect(discountOf(18000, 20000)).toBe(0)
  })
})

describe('cashChange', () => {
  it('says what to give back, or what is missing', () => {
    expect(cashChange(18000, null)).toEqual({ kind: 'none' })
    expect(cashChange(18000, 0)).toEqual({ kind: 'none' })
    expect(cashChange(18000, 15000)).toEqual({ kind: 'short', amount: 3000 })
    expect(cashChange(18000, 18000)).toEqual({ kind: 'exact' })
    expect(cashChange(18000, 20000)).toEqual({ kind: 'change', amount: 2000 })
    expect(cashChange(31000, 50000)).toEqual({ kind: 'change', amount: 19000 })
  })
})

describe('cashSuggestions', () => {
  it('offers the exact amount, then the next round notes', () => {
    expect(cashSuggestions(18000)).toEqual([18000, 20000, 30000])
    expect(cashSuggestions(13500)).toEqual([13500, 14000, 15000, 20000])
    expect(cashSuggestions(20000)).toEqual([20000, 30000])
    expect(cashSuggestions(0)).toEqual([])
  })
})

describe('isFarBelow', () => {
  it('flags a price under half of the displayed one', () => {
    expect(isFarBelow(18000, 5000)).toBe(true)
    expect(isFarBelow(18000, 9000)).toBe(false)
    expect(isFarBelow(0, 0)).toBe(false)
  })
})

const product = (extra: Partial<Product>): Product => ({
  id: 'p1',
  shop_id: 's',
  arrival_id: null,
  name: 'Robe wax modèle A',
  category: 'Robes',
  brand: 'Vlisco',
  size: 'M',
  initial_sale_price: 18000,
  quantity_on_hand: 3,
  is_unique_piece: false,
  status: 'active',
  is_test: false,
  image_path: null,
  created_at: '',
  updated_at: '',
  ...extra,
})

describe('matchesSearch', () => {
  it('finds a product by any word, without accents or case', () => {
    expect(normalize('  Chemisé LIN ')).toBe('chemise lin')
    const robe = product({})
    expect(matchesSearch(robe, 'CHN-001', '')).toBe(true)
    expect(matchesSearch(robe, 'CHN-001', 'robe')).toBe(true)
    expect(matchesSearch(robe, 'CHN-001', 'MODELE a')).toBe(true)
    expect(matchesSearch(robe, 'CHN-001', 'vlisco')).toBe(true)
    expect(matchesSearch(robe, 'CHN-001', 'chn-001')).toBe(true)
    expect(matchesSearch(robe, 'CHN-001', 'robe jean')).toBe(false)
    expect(matchesSearch(robe, undefined, 'bal-003')).toBe(false)
  })
})

describe('stockNote', () => {
  it('uses the words of the counter', () => {
    expect(stockNote({ quantity_on_hand: 3, is_unique_piece: false })).toEqual({
      text: 'Restent 3',
      low: false,
      out: false,
    })
    expect(stockNote({ quantity_on_hand: 1, is_unique_piece: false }).text).toBe('Plus que 1')
    expect(stockNote({ quantity_on_hand: 2, is_unique_piece: false }).low).toBe(true)
    expect(stockNote({ quantity_on_hand: 1, is_unique_piece: true }).text).toBe('Pièce unique')
    expect(stockNote({ quantity_on_hand: 0, is_unique_piece: false }).out).toBe(true)
  })
})
