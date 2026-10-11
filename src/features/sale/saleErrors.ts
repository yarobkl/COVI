// Sale errors in the shop's words. The server (`record_sale`) answers in English and the offline
// queue (lib/offline.ts) in technical French: neither is ever shown as is. The cart errors are
// those of `record_cart_sale` (docs/contrat-panier.md).
import { businessErrorMessage } from '../../lib/businessErrors'

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
  // Cart (record_cart_sale).
  if (m.includes('cart items must be a json array') || m.includes('invalid cart item'))
    return 'Le panier est mal enregistré. Videz-le, ajoutez à nouveau les articles, puis validez.'
  if (m.includes('cart must contain between 1 and 50 items'))
    return 'Un panier compte de 1 à 50 articles. Retirez ou ajoutez des articles, puis validez.'
  if (m.includes('duplicate product in cart'))
    return 'Cet article est deux fois dans le panier. Gardez une seule ligne et changez la quantité.'
  if (m.includes('sale total too large'))
    return 'Le total est trop élevé. Vérifiez les prix et les quantités.'
  if (m.includes('cannot mix test and real products'))
    return 'Les articles d’exemple ne se vendent pas avec les vrais. Faites deux ventes séparées.'
  // Subscription, shop, session (shared with the other screens).
  const business = businessErrorMessage(error)
  if (business) return business
  // Offline queue (lib/offline.ts).
  if (m.includes('produit absent du stock hors connexion'))
    return 'Cet article n’est pas dans le stock gardé sur ce téléphone. Attendez le retour du réseau pour le vendre.'
  if (m.includes('stock hors connexion insuffisant'))
    return remainingText(context.remaining, 'D’après ce téléphone, ')
  return 'Ça n’a pas marché. Vérifiez le réseau puis réessayez.'
}
