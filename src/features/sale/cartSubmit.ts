// Sending the cart: the single integration point between the sale screen and the server
// (`record_cart_sale`, docs/contrat-panier.md) or the offline queue.
//
// - A cart of ONE line, sold by the owner or by a cashier on their own account, goes through
//   `resilientSale` (lib/offline.ts), exactly as before the cart: `record_sale` online, kept on
//   the device when there is no network. It is never sent to `record_cart_sale` first: if that
//   call were lost on a network cut, the fallback queue would use another operation id and the
//   sale could be recorded twice.
// - A cart of SEVERAL lines goes through `record_cart_sale`, all or nothing, with one operation id
//   per cart that the screen keeps for every retry of the same cart (`operationFor`).
// - A cart sold in the name of a till-session cashier (owner's shared device, `tillSession`) is
//   ONLINE ONLY, one line or several: the offline queue (lib/offline.ts) does not carry the till
//   token, so a sale kept for later would be attributed to the owner. One line goes to
//   `record_sale`, several to `record_cart_sale`, both with `p_till_session` and the cart's
//   operation id.
//
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
  'Pas de réseau : ce panier n’a pas été enregistré. Gardez cet écran ouvert et réessayez dès que la connexion revient ; les articles seront alors vendus ensemble.'

/** Said when a sale in a till-session cashier's name cannot leave (no network). */
export const TILL_OFFLINE_TEXT =
  'Pas de réseau. Une vente au nom d’un caissier sur cet appareil a besoin du réseau. Le panier attend : réessayez dès qu’il revient.'

/** Said when the network dropped while the cart was being sent. */
export const CART_UNCERTAIN_TEXT =
  'La connexion a coupé pendant l’envoi. On ne sait pas encore si la vente est passée. Réessayez : elle ne sera pas comptée deux fois.'

export type CartSubmitResult =
  /** Recorded (`offline`: a single article kept on the device, sent when the network is back). */
  | { status: 'sold'; offline: boolean; saleId?: string }
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

/**
 * A cart sent without an answer: retried only as is, with the same operation id and the same
 * till session (the server answers a replay with the recorded sale even once it is closed).
 */
export type FrozenCart = {
  lines: Cart
  payment: string
  operation: CartOperation
  tillSession?: string
}

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

/** Said when no signed-in account is known: nothing is sent. */
export const NO_SESSION_TEXT =
  'Votre session a pris fin. Reconnectez-vous, puis validez la vente à nouveau.'

/** Thrown before anything is sent (no session): nothing can exist on the server. */
const NO_SESSION = 'Authentication required'

/**
 * The outcome of the call is unknown unless the database itself answered. A definitive refusal
 * (nothing recorded, all or nothing) carries a Postgres SQLSTATE (`P0001`, `23505`, `42501`…) or a
 * PostgREST request error (`PGRST1xx`/`PGRST2xx`: the call never ran). Everything else may hide a
 * recorded sale: network cut (`code: ''`), a gateway page 502/503/504 without code, a timeout,
 * PostgREST unable to reach the database (`PGRST0xx`). The cart is then retried as is.
 */
function isUncertain(error: unknown) {
  if (messageOf(error) === NO_SESSION) return false
  const code = (error as { code?: unknown } | null)?.code
  if (typeof code !== 'string' || code === '') return true
  if (/^PGRST\d/.test(code)) return /^PGRST0/.test(code)
  return !/^[0-9A-Z]{5}$/.test(code)
}

/** Same call as `recordCartSale` of src/lib/cartSale.ts (PR #16), plus the till session. */
async function recordCartSale(
  shopId: string,
  items: readonly CartSaleItem[],
  paymentLabel: string,
  operationId: string,
  tillSession?: string,
) {
  const { data: session } = await supabase.auth.getSession()
  if (!session.session) throw new Error(NO_SESSION)
  const { data, error } = await supabase.rpc('record_cart_sale', {
    p_shop_id: shopId,
    p_items: items.map(({ product_id, quantity, sold_unit_price }) => ({
      product_id,
      quantity,
      sold_unit_price,
    })),
    p_payment_method: paymentCode(paymentLabel),
    p_client_operation_id: operationId,
    ...(tillSession ? { p_till_session: tillSession } : {}),
  })
  if (error) throw error
  return data
}

/** One line in a till-session cashier's name: `record_sale` with the cart's operation id. */
async function recordTillLine(
  shopId: string,
  item: CartSaleItem,
  paymentLabel: string,
  operationId: string,
  tillSession: string,
) {
  const { data: session } = await supabase.auth.getSession()
  if (!session.session) throw new Error(NO_SESSION)
  const { data, error } = await supabase.rpc('record_sale', {
    p_shop_id: shopId,
    p_product_id: item.product_id,
    p_quantity: item.quantity,
    p_sold_unit_price: item.sold_unit_price,
    p_payment_method: paymentCode(paymentLabel),
    p_client_operation_id: operationId,
    p_till_session: tillSession,
  })
  if (error) throw error
  return data
}

/**
 * « item 1: product_id …, requested 3, available 2 » or « item 0: product_id …,
 * minimum_price=9000 » (DETAIL, display only).
 */
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
  /product unavailable|unique piece quantity|insufficient stock|quantity must|sold price|price below allowed minimum/i

/** The refusal in the shop's words, naming the article in cause when the server says which. */
function refusal(error: unknown, lines: Cart): CartSubmitResult {
  // Token expired or refused (PGRST30x, « JWT expired »): the call did not run, nothing was
  // recorded. Temporary: once the session is renewed, the same cart goes with the same key.
  const code = (error as { code?: unknown } | null)?.code
  if ((typeof code === 'string' && /^PGRST30\d$/.test(code)) || /\bjwt\b/i.test(messageOf(error)))
    return { status: 'refused', message: NO_SESSION_TEXT }
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
 * not used for a single line sold through `resilientSale`, whose path has its own id.
 */
export async function submitCart({
  userId,
  shopId,
  lines,
  paymentLabel,
  operationId,
  tillSession,
}: {
  /**
   * The signed-in account (AuthGate). Not sent: the server reads it from the session. Kept with a
   * waiting cart (#16) so that only this account replays it, in `shopId` — the shop it was rung up
   * in, even if another shop is open by then.
   */
  userId: string
  shopId: string
  lines: Cart
  paymentLabel: string
  operationId: string
  /**
   * Till session of the owner's shared device (« Changer de caissier »): the sale goes in the
   * cashier's name, online only.
   */
  tillSession?: string
}): Promise<CartSubmitResult> {
  // No account known: nothing is sent, nothing could be kept for a later replay.
  if (!userId) return { status: 'refused', message: NO_SESSION_TEXT }
  if (lines.length === 1 && !tillSession) {
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
  // paymentLabel }, operationId)` (userId and shopId as received here) (src/lib/cartQueue.ts),
  // persisted in IndexedDB, then `return { status: 'sold', offline: true }`. Same for the
  // `uncertain` case below, with the SAME operationId and the same content: the call may have
  // reached the server. A cart with a till session must keep waiting on screen until the queue
  // carries the till token (docs/caisse-multi-caissiers.md, « Hors connexion »).
  if (!navigator.onLine)
    return { status: 'offline', message: tillSession ? TILL_OFFLINE_TEXT : CART_WAITING_TEXT }
  try {
    const items = toCartItems(lines)
    const saleId =
      tillSession && items.length === 1
        ? await recordTillLine(shopId, items[0], paymentLabel, operationId, tillSession)
        : await recordCartSale(shopId, items, paymentLabel, operationId, tillSession)
    return {
      status: 'sold',
      offline: false,
      saleId: typeof saleId === 'string' ? saleId : undefined,
    }
  } catch (e) {
    if (isUncertain(e)) return { status: 'uncertain', message: CART_UNCERTAIN_TEXT }
    // Answered by the database (SQLSTATE) or refused by PostgREST: nothing was recorded.
    return refusal(e, lines)
  }
}
