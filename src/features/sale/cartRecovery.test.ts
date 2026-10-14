import { beforeEach, describe, expect, it } from 'vitest'
import type { Product } from '../../lib/types'
import { addToCart, type Cart } from './cart'
import { operationFor, type FrozenCart } from './cartSubmit'
import { clearUncertainCart, recoverUncertainCart, saveUncertainCart } from './cartRecovery'

const product: Product = {
  id: '11111111-1111-4111-8111-111111111111',
  shop_id: 'shop-1',
  arrival_id: null,
  name: 'Robe wax',
  category: null,
  brand: null,
  size: null,
  initial_sale_price: 10000,
  quantity_on_hand: 2,
  is_unique_piece: false,
  status: 'active',
  is_test: false,
  image_path: 'private-image-path',
  created_at: '2026-10-01T00:00:00Z',
  updated_at: '2026-10-01T00:00:00Z',
}

function uncertain(lines: Cart = addToCart([], product).cart): FrozenCart {
  const payment = 'Espèces'
  return {
    lines,
    payment,
    operation: operationFor(null, lines, payment),
  }
}

beforeEach(() => {
  sessionStorage.clear()
})

describe('recovery of a cart sent without a server response', () => {
  it('restores the same idempotency key and lines after refreshing the page', () => {
    const cart = uncertain()
    expect(saveUncertainCart('user-1', 'shop-1', cart)).toBe(true)
    const restored = recoverUncertainCart('user-1', 'shop-1')
    expect(restored?.operation.id).toBe(cart.operation.id)
    expect(restored?.lines[0].price).toBe(10000)
    expect(restored?.payment).toBe('Espèces')
  })

  it('does not show the saved cart to a different account or shop', () => {
    expect(saveUncertainCart('user-1', 'shop-1', uncertain())).toBe(true)
    expect(recoverUncertainCart('user-2', 'shop-1')).toBeNull()
    expect(recoverUncertainCart('user-1', 'shop-2')).toBeNull()
  })

  it('does not persist signed product images', () => {
    const lines: Cart = [
      { product: { ...product, image_url: 'signed-url' }, quantity: 1, price: 10000 },
    ]
    expect(saveUncertainCart('user-1', 'shop-1', uncertain(lines))).toBe(true)
    const saved = JSON.stringify(sessionStorage)
    const restored = recoverUncertainCart('user-1', 'shop-1')
    expect(saved).not.toContain('signed-url')
    expect(restored?.lines[0].product.image_url).toBeUndefined()
    expect(restored?.lines[0].product.image_path).toBeNull()
  })

  it('preserves the original cashier till token for idempotent retry', () => {
    const cart = { ...uncertain(), tillSession: 'old-till-token' }
    expect(saveUncertainCart('owner', 'shop-1', cart)).toBe(true)
    expect(recoverUncertainCart('owner', 'shop-1')?.tillSession).toBe('old-till-token')
  })

  it('refuses tampered operation signatures and malformed line quantities', () => {
    const cart = uncertain()
    expect(saveUncertainCart('user-1', 'shop-1', cart)).toBe(true)
    const [key] = Array.from({ length: sessionStorage.length }, (_, i) => sessionStorage.key(i))
    if (!key) throw new Error('Expected saved cart')
    const saved = JSON.parse(sessionStorage.getItem(key)!)
    saved.frozen.operation.signature = 'different cart'
    sessionStorage.setItem(key, JSON.stringify(saved))
    expect(recoverUncertainCart('user-1', 'shop-1')).toBeNull()
    saved.frozen.operation.signature = cart.operation.signature
    saved.frozen.lines[0].quantity = -1
    sessionStorage.setItem(key, JSON.stringify(saved))
    expect(recoverUncertainCart('user-1', 'shop-1')).toBeNull()
  })

  it('forgets the uncertain cart only on a definitive result or explicit abandonment', () => {
    expect(saveUncertainCart('user-1', 'shop-1', uncertain())).toBe(true)
    clearUncertainCart('user-1', 'shop-1')
    expect(recoverUncertainCart('user-1', 'shop-1')).toBeNull()
  })
})
