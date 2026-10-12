import { describe, expect, it } from 'vitest'
import { prepareCheckout } from './checkoutPlanning'

describe('multi-category negotiated checkout', () => {
  it('calculates the total without modifying the source basket', () => {
    const basket = Object.freeze([
      Object.freeze({ category: 'Robes', quantity: 2, negotiatedUnitPrice: 3500 }),
      Object.freeze({ category: 'Chemises', quantity: 3, negotiatedUnitPrice: 2000 }),
    ])
    expect(prepareCheckout(basket)).toEqual({
      lines: [
        { categoryKey: 'robes', quantity: 2, negotiatedUnitPrice: 3500, lineTotal: 7000 },
        { categoryKey: 'chemises', quantity: 3, negotiatedUnitPrice: 2000, lineTotal: 6000 },
      ],
      totalAmount: 13000,
      totalQuantity: 5,
    })
  })

  it('allows distinct negotiated prices for the same category', () => {
    const result = prepareCheckout([
      { category: 'Robes', quantity: 1, negotiatedUnitPrice: 3000 },
      { category: 'Robes', quantity: 1, negotiatedUnitPrice: 4000 },
    ])
    expect(result.totalAmount).toBe(7000)
  })

  it('rejects accidental duplicate lines', () => {
    expect(() => prepareCheckout([
      { category: 'Robes', quantity: 1, negotiatedUnitPrice: 3000 },
      { category: 'robes', quantity: 2, negotiatedUnitPrice: 3000 },
    ])).toThrow()
  })

  it('rejects malformed and overflowing amounts', () => {
    expect(() => prepareCheckout([])).toThrow()
    for (const price of [-1, 1.5, NaN, Infinity, 9_000_000_000_001]) {
      expect(() => prepareCheckout([{ category: 'Sacs', quantity: 1, negotiatedUnitPrice: price }])).toThrow()
    }
    expect(() => prepareCheckout([
      { category: 'Robes', quantity: 2147483647, negotiatedUnitPrice: 5000 },
    ])).toThrow()
  })

  it('accepts a zero price for a documented gift or promotional sale', () => {
    expect(prepareCheckout([
      { category: 'Accessoires', quantity: 1, negotiatedUnitPrice: 0 },
    ]).totalAmount).toBe(0)
  })
})
