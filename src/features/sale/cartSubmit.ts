// Sending the cart: the single integration point between the sale screen and the server
// (`record_cart_sale`, docs/contrat-panier.md) or the offline queue.
//
// - A cart of ONE line goes through `resilientSale` (lib/offline.ts), exactly as before the cart:
//   `record_sale` online, kept on the device when there is no network. It is never sent to
//   `record_cart_sale` first: if that call were lost on a network cut, the fallback queue would
//   use another operation id and the sale could be recorded twice.
// - A cart of SEVERAL lines goes through `record_cart_sale`, all or nothing, with one operation id
//   per cart that the screen keeps for every retry of the same cart (`operationFor`).
//   There is no durable cart queue yet (PR #16): without network the cart stays on screen, intact
//   and never split, and the seller retries. Two cases are told apart:
//   - `offline`: no network BEFORE the call, nothing was sent; the cart stays editable.
//   - `uncertain`: the call left but no answer came back (network cut, no SQLSTATE). The sale may
//     be recorded: the screen freezes the cart and only retries it as is, with the same key (the
//     server then answers with the existing sale instead of recording it twice).
import { paymentCode } from '../../lib/format'
import { resilientSale } from '../../lib/offline'
import { supabase } from '../../lib/supabase'
import { toCartItems, type Cart, type CartSaleItem } from './cart'
import { saleErrorMessage } from './saleErrors'

/** Said when a cart of several articles cannot leave (no network before sending). */
export const CART_WAITING_TEXT =
  'Pas de réseau : ce panier attend. Il sera enregistré d’un coup dès que le réseau revient. Vous pouvez aussi vendre article par article.'

/** Said when the network dropped while the cart was being sent. */
export const CART_UNCERTAIN_TEXT =
  'La connexion a coupé pendant l’envoi. On ne sait pas encore si la vente est passée. Réessayez : elle ne sera pas comptée deux fois.'

export type CartSubmitResult =
  /** Recorded (`offline`: a single article kept on the device, sent when the network is back). */
  | { status: 'sold'; offline: boolean }
  /** Not sent (no network before the call): nothing exists on the server, the cart stays editable. */
  | { status: 'offline'; message: string }
  /**
   * Sent, no answer (network cut during or after the call): the sale may be recorded. Retry ONLY
   * the same cart, unchanged, with the same operation id.
   */
  | { status: 'uncertain'; message: string }
  /** Refused by the server: nothing was recorded. `productId`: the line in cause, when known. */
  | { status: 'refused'; message: string; productId?: string }

/** The operation id of a cart, with the content it was generated for. */
export type CartOperation = { id: string; signature: string }

/** A cart sent without an answer: retried only as is, with the same operation id. */
export type FrozenCart = { lines: Cart; payment: string; operation: CartOperation }

/** What makes two carts « the same cart »: the lines sent and the payment. */
export const cartSignature = (lines: Cart, paymentLabel: string) =>
  JSON.stringify([paymentLabel, toCartItems(lines)])

/**
 * The operation id to send when the seller presses « Valider »: the previous one when it is a
 * retry of the same cart, a new one when there was none (first try, or after a success: pass
 * null) or when the cart changed meanwhile. Never reuse an id for another cart.
 */
export function operationFor(
  previous: CartOperation | null,
  lines: Cart,
  paymentLabel: string,
): CartOperation {
  const signature = cartSignature(lines, paymentLabel)
  if (previous && previous.signature === signature) return previous
  return { id: crypto.randomUUID(), signature }
}

const messageOf = (error: unknown) =>
  String(
    (error as { message?: unknown } | null | undefined)?.message ??
      (typeof error === 'string' ? error : ''),
  )

/** No answer from the server (network cut, fetch failed): the outcome of the call is unknown. */
function isNetworkFailure(error: unknown) {
  if (/fetch|network|offline|load failed|timed? ?out/i.test(messageOf(error))) return true
  // A PostgREST error without SQLSTATE: no answer from the database (contract: retryable).
  return (error as { code?: unknown } | null)?.code === ''
}

/** Same call as `recordCartSale` of src/lib/cartSale.ts (PR #16). */
async function recordCartSale(
  shopId: string,
  items: readonly CartSaleItem[],
  paymentLabel: string,
  operationId: string,
) {
  const { data: session } = await supabase.auth.getSession()
  if (!session.session) throw new Error('Authentication required')
  // `record_cart_sale` is not in the generated types of this branch yet.
  const rpc = supabase.rpc as unknown as (
    fn: string,
    args: Record<string, unknown>,
  ) => Promise<{ data: unknown; error: unknown }>
  const { data, error } = await rpc('record_cart_sale', {
    p_shop_id: shopId,
    p_items: items.map(({ product_id, quantity, sold_unit_price }) => ({
      product_id,
      quantity,
      sold_unit_price,
    })),
    p_payment_method: paymentCode(paymentLabel),
    p_client_operation_id: operationId,
  })
  if (error) throw error
  return data
}

/** « item 1: product_id …, requested 3, available 2 » (DETAIL, display only). */
function detailsOf(error: unknown, lines: Cart) {
  const details = String((error as { details?: unknown } | null)?.details ?? '')
  const index = /item (\d+)/i.exec(details)
  const available = /available (\d+)/i.exec(details)
  return {
    line: index ? lines[Number(index[1])] : undefined,
    available: available ? Number(available[1]) : undefined,
  }
}

const PRODUCT_ERRORS =
  /product unavailable|unique piece quantity|insufficient stock|quantity must|sold price/i

/** The refusal in the shop's words, naming the article in cause when the server says which. */
function refusal(error: unknown, lines: Cart): CartSubmitResult {
  const { line, available } = detailsOf(error, lines)
  const message = saleErrorMessage(error, {
    remaining: available ?? (line ? Number(line.product.quantity_on_hand) : undefined),
  })
  if (line && PRODUCT_ERRORS.test(messageOf(error)))
    return {
      status: 'refused',
      productId: line.product.id,
      message: `${line.product.name} : ${message.charAt(0).toLowerCase()}${message.slice(1)}`,
    }
  return { status: 'refused', message }
}

/**
 * Sends the cart. `operationId` comes from `operationFor` (one per cart, reused on retries); it is
 * not used for a single line, whose `resilientSale` path has its own id.
 */
export async function submitCart({
  shopId,
  lines,
  paymentLabel,
  operationId,
}: {
  shopId: string
  lines: Cart
  paymentLabel: string
  operationId: string
}): Promise<CartSubmitResult> {
  if (lines.length === 1) {
    const [line] = lines
    try {
      const result = await resilientSale({
        shopId,
        productId: line.product.id,
        quantity: line.quantity,
        soldUnitPrice: line.price,
        paymentLabel,
      })
      return { status: 'sold', offline: result.offline }
    } catch (e) {
      return {
        status: 'refused',
        message: saleErrorMessage(e, { remaining: Number(line.product.quantity_on_hand) }),
      }
    }
  }

  // TODO(#16): without network, hand the cart to the durable queue of ChatGPT's PR #16 instead
  // of waiting on screen: `createQueuedCart({ userId, shopId, items: toCartItems(lines),
  // paymentLabel }, operationId)` (src/lib/cartQueue.ts), persisted in IndexedDB, then
  // `return { status: 'sold', offline: true }`. Same for the `uncertain` case below, with the SAME
  // operationId and the same content: the call may have reached the server.
  if (!navigator.onLine) return { status: 'offline', message: CART_WAITING_TEXT }
  try {
    await recordCartSale(shopId, toCartItems(lines), paymentLabel, operationId)
    return { status: 'sold', offline: false }
  } catch (e) {
    if (isNetworkFailure(e)) return { status: 'uncertain', message: CART_UNCERTAIN_TEXT }
    // An error with a SQLSTATE: all or nothing, nothing was recorded.
    return refusal(e, lines)
  }
}
