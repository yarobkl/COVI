import { describe, expect, it } from 'vitest'
import { cartBelongsToUser, createQueuedCart, validateCart } from './cartQueue'

const A = '11111111-1111-4111-8111-111111111111'
const B = '22222222-2222-4222-8222-222222222222'
const item = { product_id: A, quantity: 2, sold_unit_price: 4500 }

describe('offline cart operation', () => {
  it('snapshots lines and preserves the provided operation key', () => {
    const input = [item]
    const cart = createQueuedCart({ userId: 'u1', shopId: 's1', items: input, paymentLabel: 'Espèces' }, B)
    input[0] = { ...item, quantity: 9 }
    expect(cart.items).toEqual([item])
    expect(cart.id).toBe(B)
    expect(cart.attempts).toBe(0)
  })
  it('keeps an operation scoped to the originating account and shop', () => {
    const cart = createQueuedCart({ userId: 'u1', shopId: 'shop-A', items: [item], paymentLabel: 'Espèces' }, B)
    expect(cartBelongsToUser(cart, 'u1')).toBe(true)
    expect(cartBelongsToUser(cart, 'u2')).toBe(false)
    expect(cart.shopId).toBe('shop-A')
  })
  it('rejects empty and oversized carts', () => {
    expect(() => validateCart([])).toThrow()
    expect(() => validateCart(Array.from({ length: 51 }, () => item))).toThrow()
  })
  it('rejects duplicate products, invalid quantities and negative prices', () => {
    expect(() => validateCart([item, item])).toThrow()
    expect(() => validateCart([{ ...item, quantity: 1.5 }])).toThrow()
    expect(() => validateCart([{ ...item, quantity: 0 }])).toThrow()
    expect(() => validateCart([{ ...item, sold_unit_price: -1 }])).toThrow()
    expect(() => validateCart([{ ...item, sold_unit_price: Infinity }])).toThrow()
  })
  it('accepts a multi-item cart', () => {
    expect(validateCart([item, { product_id: B, quantity: 1, sold_unit_price: 0 }])).toHaveLength(2)
  })
})
