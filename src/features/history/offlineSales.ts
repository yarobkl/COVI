// Sales kept on this device: those waiting for the network, and those the account refused when
// they were sent (lib/offline.ts keeps the product id, amount, date and the server's reason).
import type { PendingSale, RejectedSale } from '../../lib/offline'

/**
 * Why a sale sent later was refused, in the shop's words and in the past tense (it happened while
 * the seller was away). The server answers in English (`record_sale`); nothing technical is shown.
 */
export function rejectionReason(reason: string | null | undefined): string {
  const m = (reason ?? '').toLowerCase()
  if (m.includes('product unavailable'))
    return 'Il n’était plus en stock : il a sans doute été vendu sur un autre appareil.'
  if (m.includes('insufficient stock'))
    return 'Il n’en restait plus assez : une partie a sans doute été vendue sur un autre appareil.'
  if (m.includes('unique piece quantity'))
    return 'C’est une pièce unique : elle ne pouvait être vendue qu’une fois.'
  if (m.includes('quantity must be positive')) return 'La quantité notée n’était pas bonne.'
  if (m.includes('sold price cannot be negative')) return 'Le prix noté n’était pas bon.'
  if (m.includes('invalid payment method')) return 'Le moyen de paiement n’a pas été reconnu.'
  if (m.includes('authentication required') || m.includes('session'))
    return 'Votre session avait pris fin au moment de l’envoi.'
  return 'Le compte ne l’a pas acceptée.'
}

/** A sale kept on this device, ready to show: article, amount, how and when it was paid. */
export type DeviceSale = {
  id: string
  name: string
  quantity: number
  amount: number
  /** Label chosen at checkout (« Espèces »…). */
  paymentLabel: string
  at: Date
  /** Only for refused sales: why, in the shop's words. */
  reason?: string
}

/** Names of the products kept on this device, by id (the cached stock). */
export type ProductNames = ReadonlyMap<string, string>

const base = (s: PendingSale, names: ProductNames): DeviceSale => ({
  id: s.id,
  name: names.get(s.productId) ?? 'Un article',
  quantity: Number(s.quantity),
  amount: Number(s.soldUnitPrice) * Number(s.quantity),
  paymentLabel: s.paymentLabel,
  at: new Date(s.createdAt),
})

/** Sales waiting for the network, oldest first. */
export const waitingSales = (pending: PendingSale[], names: ProductNames): DeviceSale[] =>
  pending.map((s) => base(s, names)).sort((a, b) => a.at.getTime() - b.at.getTime())

/** Refused sales the seller has not acknowledged yet, most recent first. */
export const refusedSales = (rejected: RejectedSale[], names: ProductNames): DeviceSale[] =>
  rejected
    .filter((s) => !s.dismissed)
    .map((s) => ({ ...base(s, names), reason: rejectionReason(s.reason) }))
    .sort((a, b) => b.at.getTime() - a.at.getTime())
