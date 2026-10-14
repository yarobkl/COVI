/**
 * Recovery for a cart whose request may have reached the database, but whose response was lost.
 * Never create a new operation id for this cart after a refresh: that could charge the same
 * transaction twice if stock is still available. This is NOT a durable offline sales queue.
 *
 * sessionStorage survives a tab reload, but is cleared at the end of the browser session. The
 * record is scoped to the signed-in account and shop; it deliberately excludes signed image URLs.
 */
import { MAX_CART_LINES } from './cart'
import { cartSignature, type FrozenCart } from './cartSubmit'

const PREFIX = 'covi:uncertain-cart:v1:'
const MAX_BYTES = 120_000
const key = (userId: string, shopId: string) => `${PREFIX}${userId}:${shopId}`

type Saved = { version: 1; userId: string; shopId: string; frozen: FrozenCart }

export function saveUncertainCart(userId: string, shopId: string, frozen: FrozenCart): boolean {
  if (!userId || !shopId) return false
  try {
    // Do not persist temporary signed URLs from the stock cache.
    const lines = frozen.lines.map((line) => ({
      ...line,
      product: { ...line.product, image_url: undefined, image_path: null },
    }))
    const envelope: Saved = {
      version: 1,
      userId,
      shopId,
      frozen: { ...frozen, lines },
    }
    const json = JSON.stringify(envelope)
    if (json.length > MAX_BYTES) return false
    sessionStorage.setItem(key(userId, shopId), json)
    return true
  } catch {
    return false
  }
}

export function recoverUncertainCart(userId: string, shopId: string): FrozenCart | null {
  if (!userId || !shopId) return null
  try {
    const value = sessionStorage.getItem(key(userId, shopId))
    if (!value || value.length > MAX_BYTES) return null
    const saved = JSON.parse(value) as Saved
    if (
      saved.version !== 1 ||
      saved.userId !== userId ||
      saved.shopId !== shopId ||
      !saved.frozen ||
      !Array.isArray(saved.frozen.lines) ||
      saved.frozen.lines.length < 1 ||
      saved.frozen.lines.length > MAX_CART_LINES ||
      typeof saved.frozen.payment !== 'string' ||
      !saved.frozen.payment ||
      typeof saved.frozen.operation?.id !== 'string' ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        saved.frozen.operation.id,
      ) ||
      (saved.frozen.tillSession !== undefined &&
        typeof saved.frozen.tillSession !== 'string')
    ) return null

    for (const line of saved.frozen.lines) {
      if (
        !line ||
        typeof line.product?.id !== 'string' ||
        typeof line.product.name !== 'string' ||
        !Number.isSafeInteger(line.quantity) ||
        line.quantity < 1 ||
        !Number.isFinite(line.price) ||
        line.price <= 0
      ) return null
    }

    // An operation id is valid only for the exact lines and payment originally sent.
    if (saved.frozen.operation.signature !== cartSignature(saved.frozen.lines, saved.frozen.payment))
      return null
    return saved.frozen
  } catch {
    return null
  }
}

export function clearUncertainCart(userId: string, shopId: string): void {
  try {
    sessionStorage.removeItem(key(userId, shopId))
  } catch {
    // Storage may be disabled. The in-memory cart is still discarded by the caller.
  }
}
