// The cart (« panier ») of the sale screen: pure functions, kept apart from the components to be
// tested. One line per article, keyed by the product id; the server contract is
// docs/contrat-panier.md (`record_cart_sale`).
import type { Product } from '../../lib/types'
import { discountOf } from './saleMath'

/**
 * One line sent to `record_cart_sale`, exactly (no other key is accepted by the server).
 * Mirrors `CartSaleItem` of src/lib/cartSale.ts in PR #16 (offline cart queue): replace this
 * declaration by `import type { CartSaleItem } from '../../lib/cartSale'` once #16 lands.
 */
export type CartSaleItem = { product_id: string; quantity: number; sold_unit_price: number }

/** The server refuses a cart of more than 50 lines. */
export const MAX_CART_LINES = 50

/** An article in the cart: the product as shown when it was added, how many, the agreed price. */
export type CartLine = {
  product: Product
  quantity: number
  /** Unit price agreed with the customer (starts at the displayed price). */
  price: number
}

export type Cart = readonly CartLine[]

/** What touching a tile did, to tell the seller. */
export type AddOutcome = 'added' | 'more' | 'max' | 'full'

/** Displayed price of the article (prix affiché). */
export const displayedPrice = (product: Product) => Number(product.initial_sale_price)

/** How many of this article the cart may hold: 1 for a unique piece, otherwise the stock. */
export const maxQuantity = (product: Product) =>
  product.is_unique_piece
    ? Math.min(1, Math.max(0, Number(product.quantity_on_hand)))
    : Math.max(0, Math.floor(Number(product.quantity_on_hand)))

export const lineOf = (cart: Cart, productId: string) =>
  cart.find((line) => line.product.id === productId)

/**
 * Touching an article: a new line at the displayed price, or one more of an article already in
 * the cart (never more than the stock, a unique piece stays at 1). At most 50 lines.
 */
export function addToCart(cart: Cart, product: Product): { cart: Cart; outcome: AddOutcome } {
  const max = maxQuantity(product)
  const line = lineOf(cart, product.id)
  if (line) {
    if (line.quantity >= max) return { cart, outcome: 'max' }
    return {
      cart: cart.map((l) => (l === line ? { ...l, quantity: l.quantity + 1 } : l)),
      outcome: 'more',
    }
  }
  if (max < 1) return { cart, outcome: 'max' }
  if (cart.length >= MAX_CART_LINES) return { cart, outcome: 'full' }
  return {
    cart: [...cart, { product, quantity: 1, price: displayedPrice(product) }],
    outcome: 'added',
  }
}

/** New quantity of a line, kept between 1 and the stock. */
export function setQuantity(cart: Cart, productId: string, quantity: number): Cart {
  return cart.map((line) => {
    if (line.product.id !== productId) return line
    const max = Math.max(1, maxQuantity(line.product))
    const q = Math.min(max, Math.max(1, Math.floor(quantity) || 1))
    return q === line.quantity ? line : { ...line, quantity: q }
  })
}

/** Unit price agreed for a line (never negative). */
export function setPrice(cart: Cart, productId: string, price: number): Cart {
  const p = Math.max(0, Number.isFinite(price) ? price : 0)
  return cart.map((line) =>
    line.product.id === productId && line.price !== p ? { ...line, price: p } : line,
  )
}

export const removeLine = (cart: Cart, productId: string): Cart =>
  cart.filter((line) => line.product.id !== productId)

/** Pieces in the cart (2 robes + 1 jean = 3). */
export const cartCount = (cart: Cart) => cart.reduce((n, line) => n + line.quantity, 0)

/** What the customer pays: Σ quantity × agreed price. */
export const cartTotal = (cart: Cart) =>
  cart.reduce((sum, line) => sum + line.quantity * line.price, 0)

/** Total at the displayed prices. */
export const cartDisplayedTotal = (cart: Cart) =>
  cart.reduce((sum, line) => sum + line.quantity * displayedPrice(line.product), 0)

/** Discount of one line against the displayed price (0 when sold at or above it). */
export const lineDiscount = (line: CartLine) =>
  discountOf(displayedPrice(line.product), line.price, line.quantity)

/** Discount granted on the whole cart, line by line. */
export const cartDiscount = (cart: Cart) => cart.reduce((sum, line) => sum + lineDiscount(line), 0)

/** The cart in the exact shape of `record_cart_sale` (`p_items`): three keys, numbers. */
export const toCartItems = (cart: Cart): CartSaleItem[] =>
  cart.map((line) => ({
    product_id: line.product.id,
    quantity: line.quantity,
    sold_unit_price: line.price,
  }))

/**
 * The cart after the stock was reloaded: each line takes the fresh product (name, stock) and its
 * quantity is kept within the new stock. A line whose article is gone stays as it is: the server
 * will say it is no longer for sale, and the seller removes it.
 */
export function refreshLines(cart: Cart, products: readonly Product[]): Cart {
  if (!cart.length) return cart
  const byId = new Map(products.map((p) => [p.id, p]))
  return cart.map((line) => {
    const fresh = byId.get(line.product.id)
    if (!fresh) return line
    const quantity = Math.min(line.quantity, Math.max(1, maxQuantity(fresh)))
    return { ...line, product: fresh, quantity }
  })
}

/** One article of a validated sale. */
export type SoldLine = Pick<CartLine, 'product' | 'quantity' | 'price'>

/** A validated sale, for the « Vendu. » screen. */
export type SoldSale = {
  lines: SoldLine[]
  payment: string
  /** Cash handed over (display only, never stored). */
  received: number | null
  /** Kept on the device, to be sent when the network comes back. */
  offline: boolean
  at: Date
}

/** Total of a validated sale. */
export const soldTotal = (sale: SoldSale) =>
  sale.lines.reduce((sum, line) => sum + line.price * line.quantity, 0)
