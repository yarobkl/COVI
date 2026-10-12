/** Pure order lifecycle for the future COVI omnichannel queue.
 * No database updates, stock decrement or payment capture happen here.
 */
export type OrderChannel = 'qr' | 'social' | 'manual'
export type OrderStatus =
  | 'submitted'
  | 'approved'
  | 'reserved'
  | 'paid'
  | 'cancelled'
  | 'expired'

export type OrderEvent =
  | 'approve'
  | 'reserve'
  | 'confirm_payment'
  | 'cancel'
  | 'expire'

const transitions: Record<OrderStatus, Partial<Record<OrderEvent, OrderStatus>>> = {
  submitted: { approve: 'approved', cancel: 'cancelled', expire: 'expired' },
  approved: { reserve: 'reserved', confirm_payment: 'paid', cancel: 'cancelled', expire: 'expired' },
  reserved: { confirm_payment: 'paid', cancel: 'cancelled', expire: 'expired' },
  paid: {},
  cancelled: {},
  expired: {},
}

export function nextOrderStatus(status: OrderStatus, event: OrderEvent): OrderStatus {
  const next = transitions[status]?.[event]
  if (!next) throw new Error(`Transition de commande interdite : ${status} → ${event}`)
  return next
}

export function requiresStockDeduction(
  previous: OrderStatus,
  next: OrderStatus,
): boolean {
  return previous !== 'paid' && next === 'paid'
}

export function releasesReservation(
  previous: OrderStatus,
  next: OrderStatus,
): boolean {
  return previous === 'reserved' && (next === 'cancelled' || next === 'expired')
}

export function validateOrderChannel(channel: string): OrderChannel {
  if (channel === 'qr' || channel === 'social' || channel === 'manual') return channel
  throw new Error('Canal de commande inconnu.')
}

/** Only a server-side atomic payment RPC may actually perform stock deduction.
 * This helper is a business rule, NOT an idempotency or concurrency guarantee.
 */
