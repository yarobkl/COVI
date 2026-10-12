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

/** Cashier-entered details. The first name is an attestation, NOT authentication.
 * The RPC must separately derive the authorized user ID from auth.uid().
 */
export type ManualCashierAttestation = {
  method: ManualPaymentMethod
  cashierFirstName: string
  externalReference?: string
}

/** A server-recorded confirmation additionally contains verified audit metadata. */
export type ManualPaymentConfirmation = ManualCashierAttestation & {
  receivedByUserId: string
  confirmedAt: string
}

export function prepareManualCashierAttestation(
  input: ManualCashierAttestation,
): ManualCashierAttestation {
  if (!['cash', 'mobile_money', 'other'].includes(input.method))
    throw new Error('Moyen de paiement inconnu.')

  if (typeof input.cashierFirstName !== 'string')
    throw new Error('Le prénom de la personne qui encaisse est obligatoire.')

  const cashierFirstName = input.cashierFirstName.normalize('NFC').trim().replace(/\s+/gu, ' ')
  if (cashierFirstName.length < 1 || cashierFirstName.length > 60 ||
      !/^[\p{L}\p{M}]+(?:[ '\u2019-][\p{L}\p{M}]+)*$/u.test(cashierFirstName))
    throw new Error('Saisissez un prénom valide (60 caractères maximum).')

  if (input.externalReference !== undefined && typeof input.externalReference !== 'string')
    throw new Error('Référence de paiement invalide.')
  const externalReference = input.externalReference?.trim()
  if (externalReference && externalReference.length > 120)
    throw new Error('Référence de paiement trop longue.')

  return {
    method: input.method,
    cashierFirstName,
    ...(externalReference ? { externalReference } : {}),
  }
}

export function validateManualPaymentConfirmation(
  value: ManualPaymentConfirmation,
): ManualPaymentConfirmation {
  const attestation = prepareManualCashierAttestation(value)
  if (typeof value.receivedByUserId !== 'string' || !value.receivedByUserId.trim())
    throw new Error('Le compte du vendeur doit être identifié.')
  if (typeof value.confirmedAt !== 'string' ||
      !value.confirmedAt.trim() || !Number.isFinite(Date.parse(value.confirmedAt)))
    throw new Error('Date de confirmation invalide.')
  return { ...attestation, receivedByUserId: value.receivedByUserId, confirmedAt: value.confirmedAt }
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
