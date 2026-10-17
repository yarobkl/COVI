import type { OrderChannel } from '../../lib/publicOrders'

/** A permanent QR/social URL is a bearer token for SUBMITTING ONLY.
 * The token never permits price approval, stock updates or payment confirmation.
 */
export function parseGuestOrderHash(hash: string): { token: string; channel: OrderChannel } | null {
  const match =
    /^#\/commander\/([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})(?:\?via=(qr|social))?$/i.exec(
      hash,
    )
  if (!match) return null
  return { token: match[1].toLowerCase(), channel: match[2] === 'social' ? 'social' : 'qr' }
}

/** Per-order tracking is distinct from the shop's permanent QR public token.
 * Only a high-entropy token issued on a successful request opens its receipt.
 */
export function parseGuestTrackingHash(hash: string): string | null {
  const match = /^#\/suivi\/([0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12})$/i.exec(hash)
  return match ? match[1].toLowerCase() : null
}
