import { describe, expect, it } from 'vitest'
import type { Product } from '../../lib/types'
import {
  addToCart,
  cartCount,
  cartDiscount,
  cartDisplayedTotal,
  cartTotal,
  MAX_CART_LINES,
  maxQuantity,
  refreshLines,
  removeLine,
  setPrice,
  setQuantity,
  toCartItems,
  type Cart,
} from './cart'

const product = (id: string, extra: Partial<Product> = {}): Product => ({
  id,
  shop_id: 'shop-1',
  arrival_id: null,
  name: `Article ${id}`,
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

const robe = product('p1', { name: 'Robe wax', initial_sale_price: 18000, quantity_on_hand: 2 })
const veste = product('p2', { name: 'Veste', is_unique_piece: true, quantity_on_hand: 1 })

describe('addToCart', () => {
  it('adds a new line at the displayed price, quantity 1', () => {
    const { cart, outcome } = addToCart([], robe)
    expect(outcome).toBe('added')
    expect(cart).toEqual([{ product: robe, quantity: 1, price: 18000 }])
  })

  it('touching an article already in the cart adds one more, up to the stock', () => {
    let cart: Cart = addToCart([], robe).cart
    const second = addToCart(cart, robe)
    expect(second.outcome).toBe('more')
    cart = second.cart
    expect(cart).toHaveLength(1)
    expect(cart[0].quantity).toBe(2)
    const third = addToCart(cart, robe)
    expect(third.outcome).toBe('max')
    expect(third.cart).toBe(cart)
  })

  it('keeps a unique piece at 1', () => {
    const cart = addToCart([], veste).cart
    const again = addToCart(cart, veste)
    expect(again.outcome).toBe('max')
    expect(again.cart[0].quantity).toBe(1)
    expect(maxQuantity(product('x', { is_unique_piece: true, quantity_on_hand: 5 }))).toBe(1)
  })

  it('does not add an article out of stock', () => {
    const out = product('p9', { quantity_on_hand: 0 })
    expect(addToCart([], out)).toEqual({ cart: [], outcome: 'max' })
  })

  it('holds 50 different articles at most, but still adds one more of an article inside', () => {
    let cart: Cart = []
    for (let i = 0; i < MAX_CART_LINES; i++) cart = addToCart(cart, product(`p${i}`)).cart
    expect(cart).toHaveLength(50)
    const full = addToCart(cart, product('p-new'))
    expect(full.outcome).toBe('full')
    expect(full.cart).toHaveLength(50)
    expect(addToCart(cart, product('p0')).cart[0].quantity).toBe(2)
  })
})

describe('setQuantity, setPrice, removeLine', () => {
  const start = addToCart(addToCart([], robe).cart, veste).cart

  it('keeps the quantity between 1 and the stock', () => {
    expect(setQuantity(start, 'p1', 2)[0].quantity).toBe(2)
    expect(setQuantity(start, 'p1', 9)[0].quantity).toBe(2)
    expect(setQuantity(start, 'p1', 0)[0].quantity).toBe(1)
    expect(setQuantity(start, 'p2', 3)[1].quantity).toBe(1)
  })

  it('changes the agreed unit price of one line only, never below 0', () => {
    const cart = setPrice(start, 'p1', 15000)
    expect(cart[0].price).toBe(15000)
    expect(cart[1].price).toBe(10000)
    expect(setPrice(start, 'p1', -5)[0].price).toBe(0)
  })

  it('removes a line', () => {
    expect(removeLine(start, 'p1').map((l) => l.product.id)).toEqual(['p2'])
    expect(removeLine(start, 'nope')).toHaveLength(2)
  })
})

describe('totals', () => {
  it('adds quantity × agreed price; the discount is counted line by line', () => {
    let cart = addToCart(addToCart([], robe).cart, veste).cart
    cart = setQuantity(cart, 'p1', 2)
    cart = setPrice(cart, 'p1', 15000)
    cart = setPrice(cart, 'p2', 12000) // above the displayed price: no discount
    expect(cartCount(cart)).toBe(3)
    expect(cartTotal(cart)).toBe(2 * 15000 + 12000)
    expect(cartDisplayedTotal(cart)).toBe(2 * 18000 + 10000)
    expect(cartDiscount(cart)).toBe(6000)
    expect(cartTotal([])).toBe(0)
  })
})

describe('toCartItems', () => {
  it('produces exactly the record_cart_sale lines: three keys, numbers, one per product', () => {
    let cart = addToCart(addToCart(addToCart([], robe).cart, veste).cart, robe).cart
    cart = setPrice(cart, 'p2', 9000)
    const items = toCartItems(cart)
    expect(items).toEqual([
      { product_id: 'p1', quantity: 2, sold_unit_price: 18000 },
      { product_id: 'p2', quantity: 1, sold_unit_price: 9000 },
    ])
    for (const item of items) {
      expect(Object.keys(item).sort()).toEqual(['product_id', 'quantity', 'sold_unit_price'])
      expect(typeof item.quantity).toBe('number')
      expect(typeof item.sold_unit_price).toBe('number')
    }
    expect(JSON.parse(JSON.stringify(items))).toEqual(items)
  })

  it('reads numbers even when the product price comes as a string', () => {
    const odd = product('p3', { initial_sale_price: '7500' as unknown as number })
    expect(toCartItems(addToCart([], odd).cart)[0].sold_unit_price).toBe(7500)
  })
})

describe('refreshLines', () => {
  it('takes the fresh stock and keeps the quantity within it', () => {
    let cart = addToCart([], robe).cart
    cart = setQuantity(cart, 'p1', 2)
    const fresh = { ...robe, quantity_on_hand: 1 }
    const next = refreshLines(cart, [fresh])
    expect(next[0].product).toBe(fresh)
    expect(next[0].quantity).toBe(1)
    expect(refreshLines(cart, [])).toEqual(cart)
  })
})
