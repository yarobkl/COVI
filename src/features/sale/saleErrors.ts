// Sale errors in the shop's words. The server (`record_sale`) answers in English and the offline
// queue (lib/offline.ts) in technical French: neither is ever shown as is.

const messageOf = (error: unknown) =>
  String(
    (error as { message?: unknown } | null | undefined)?.message ??
      (typeof error === 'string' ? error : ''),
  )

const remainingText = (remaining: number | undefined, prefix: string) =>
  remaining !== undefined && remaining > 0
    ? `${prefix}il n’en reste que ${remaining}. Baissez la quantité.`
    : `${prefix}il n’en reste pas assez. Baissez la quantité.`

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

/**
 * What to tell the seller when a sale is refused: what happened and what to do. `remaining` is the
 * quantity the screen believes is left, used in « Il n’en reste que 1 ».
 */
export function saleErrorMessage(error: unknown, context: { remaining?: number } = {}): string {
  const m = messageOf(error).toLowerCase()
  if (m.includes('unique piece quantity')) return 'C’est une pièce unique : la quantité est 1.'
  if (m.includes('insufficient stock')) return capitalize(remainingText(context.remaining, ''))
  if (m.includes('product unavailable'))
    return 'Cet article n’est plus en stock. Il a peut-être déjà été vendu.'
  if (m.includes('quantity must be positive')) return 'Indiquez au moins 1 pièce.'
  if (m.includes('sold price cannot be negative')) return 'Indiquez le prix auquel vous avez vendu.'
  if (m.includes('invalid payment method')) return 'Choisissez comment la cliente a payé.'
  if (m.includes('authentication required') || m.includes('session introuvable'))
    return 'Votre session a pris fin. Reconnectez-vous, puis validez la vente à nouveau.'
  if (m.includes('operation id is required'))
    return 'Ça n’a pas marché. Validez la vente une nouvelle fois.'
  // Offline queue (lib/offline.ts).
  if (m.includes('produit absent du stock hors connexion'))
    return 'Cet article n’est pas dans le stock gardé sur ce téléphone. Attendez le retour du réseau pour le vendre.'
  if (m.includes('stock hors connexion insuffisant'))
    return remainingText(context.remaining, 'D’après ce téléphone, ')
  return 'Ça n’a pas marché. Vérifiez le réseau puis réessayez.'
}
