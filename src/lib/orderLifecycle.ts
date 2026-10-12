/** Pure order lifecycle for the future COVI omnichannel queue.
 * Payments are received outside COVI and manually verified by the cashier.
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

export type ManualPaymentMethod = 'cash' | 'mobile_money' | 'other'

export type ManualPaymentConfirmation = {
  method: ManualPaymentMethod
  receivedByUserId: string
  confirmedAt: string
  externalReference?: string
}

export function validateManualPaymentConfirmation(value: ManualPaymentConfirmation): ManualPaymentConfirmation {
  if (!['cash', 'mobile_money', 'other'].includes(value.method))
    throw new Error('Moyen de paiement inconnu.')
  if (!value.receivedByUserId.trim()) throw new Error('Le vendeur doit être identifié.')
  if (!value.confirmedAt.trim() || !Number.isFinite(Date.parse(value.confirmedAt)))
    throw new Error('Date de confirmation invalide.')
  if (value.externalReference && value.externalReference.length > 120)
    throw new Error('Référence de paiement trop longue.')
  return value
}

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

/** Only a server-side atomic cashier-confirmation RPC may actually perform stock deduction.
 * COVI never claims to verify mobile-money settlement or capture payment via an API.
 * This helper is a business rule, NOT an idempotency or concurrency guarantee.
 */
