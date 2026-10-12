import { describe, expect, it } from 'vitest'
import { aggregateCategoryStock, categoryKey, STOCK_CATEGORIES } from './stockCategories'

describe('central stock categories', () => {
  it('offers the main second-hand retail categories', () => {
    const keys = STOCK_CATEGORIES.map((x) => x.key)
    expect(keys).toContain('sous-vetements')
    expect(keys).toContain('sacs')
    expect(keys).toContain('linge-maison')
    expect(new Set(keys).size).toBe(keys.length)
  })

  it('groups case, accents and whitespace consistently', () => {
    expect(categoryKey('  T-Shirts  ')).toBe('t-shirts')
    expect(categoryKey('Vêtements enfants')).toBe('vetements-enfants')
    expect(aggregateCategoryStock([
      { category: 'Robes', quantity: 4 },
      { category: ' robes ', quantity: 3 },
      { category: 'ROBES', quantity: 2 },
    ])).toEqual([{ category: 'robes', quantity: 9 }])
  })

  it('does not change its input', () => {
    const rows = Object.freeze([Object.freeze({ category: 'Sacs', quantity: 2 })])
    expect(aggregateCategoryStock(rows)).toEqual([{ category: 'sacs', quantity: 2 }])
  })

  it('rejects invalid and unsafe quantities', () => {
    for (const quantity of [-1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
      expect(() => aggregateCategoryStock([{ category: 'Robes', quantity }])).toThrow()
    }
    expect(() => aggregateCategoryStock([
      { category: 'Sacs', quantity: Number.MAX_SAFE_INTEGER },
      { category: 'Sacs', quantity: 1 },
    ])).toThrow()
  })

  it('returns an empty inventory for an empty reception', () => {
    expect(aggregateCategoryStock([])).toEqual([])
  })
})
