import type { CartSaleItem } from './cartSale'

export type QueuedCart = {
  id: string
  userId: string
  shopId: string
  items: CartSaleItem[]
  paymentLabel: string
  createdAt: string
  attempts: number
  lastError?: string
}

/** Validate a whole cart before giving it a durable idempotency key. */
export function validateCart(items: readonly CartSaleItem[]): CartSaleItem[] {
  if (items.length < 1 || items.length > 50) throw new Error('Le panier doit contenir entre 1 et 50 références.')
  const ids = new Set<string>()
  return items.map((item) => {
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(item.product_id))
      throw new Error('Identifiant produit invalide.')
    if (ids.has(item.product_id.toLowerCase())) throw new Error('Produit présent deux fois dans le panier.')
    ids.add(item.product_id.toLowerCase())
    if (!Number.isSafeInteger(item.quantity) || item.quantity < 1 || item.quantity > 2147483647)
      throw new Error('Quantité invalide.')
    if (!Number.isFinite(item.sold_unit_price) || item.sold_unit_price < 0)
      throw new Error('Prix de vente invalide.')
    return { product_id: item.product_id, quantity: item.quantity, sold_unit_price: item.sold_unit_price }
  })
}

/** Snapshot of the cart; never mutate or regenerate its id during synchronization. */
export function createQueuedCart(
  input: { userId: string; shopId: string; items: readonly CartSaleItem[]; paymentLabel: string },
  operationId: string = crypto.randomUUID(),
): QueuedCart {
  if (!input.userId || !input.shopId || !operationId) throw new Error('Compte, boutique ou opération manquante.')
  return {
    id: operationId,
    userId: input.userId,
    shopId: input.shopId,
    items: validateCart(input.items),
    paymentLabel: input.paymentLabel,
    createdAt: new Date().toISOString(),
    attempts: 0,
  }
}

/** A queue entry can only be replayed by the account that originally created it. */
export const cartBelongsToUser = (cart: QueuedCart, userId: string) => cart.userId === userId
