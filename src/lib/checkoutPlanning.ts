/** Pure preparation for COVI's future cashier queue.
 * No Supabase calls, no stock mutation, no payment confirmation.
 */
import { categoryKey } from './stockCategories'

export type CheckoutLine = {
  category: string
  quantity: number
  negotiatedUnitPrice: number
}

export type PreparedCheckoutLine = {
  categoryKey: string
  quantity: number
  negotiatedUnitPrice: number
  lineTotal: number
}

export type PreparedCheckout = {
  lines: PreparedCheckoutLine[]
  totalAmount: number
  totalQuantity: number
}

const MAX_XAF_AMOUNT = 9_000_000_000_000

export function prepareCheckout(lines: readonly CheckoutLine[]): PreparedCheckout {
  if (lines.length < 1 || lines.length > 100)
    throw new Error('La vente doit contenir entre 1 et 100 lignes.')

  const prepared: PreparedCheckoutLine[] = []
  let totalAmount = 0
  let totalQuantity = 0

  for (const line of lines) {
    if (typeof line.category !== 'string' || !line.category.trim() || line.category.length > 80)
      throw new Error('Catégorie invalide.')
    if (!Number.isSafeInteger(line.quantity) || line.quantity < 1 || line.quantity > 2147483647)
      throw new Error('Quantité de vente invalide.')
    if (
      !Number.isSafeInteger(line.negotiatedUnitPrice) ||
      line.negotiatedUnitPrice < 0 ||
      line.negotiatedUnitPrice > MAX_XAF_AMOUNT
    )
      throw new Error('Prix négocié invalide.')
    const lineTotal = line.quantity * line.negotiatedUnitPrice
    if (!Number.isSafeInteger(lineTotal) || lineTotal > MAX_XAF_AMOUNT)
      throw new Error('Montant de ligne trop élevé.')
    totalAmount += lineTotal
    totalQuantity += line.quantity
    if (
      !Number.isSafeInteger(totalAmount) ||
      totalAmount > MAX_XAF_AMOUNT ||
      !Number.isSafeInteger(totalQuantity) ||
      totalQuantity > 2147483647
    )
      throw new Error('Total de vente trop élevé.')
    prepared.push({
      categoryKey: categoryKey(line.category),
      quantity: line.quantity,
      negotiatedUnitPrice: line.negotiatedUnitPrice,
      lineTotal,
    })
  }

  // Preserve distinct negotiated prices, but reject duplicate identical category/price
  // lines to avoid accidental double-click additions.
  const seen = new Set<string>()
  for (const line of prepared) {
    const key = line.categoryKey + ':' + line.negotiatedUnitPrice
    if (seen.has(key)) throw new Error('Ligne identique en double dans le panier.')
    seen.add(key)
  }

  return { lines: prepared, totalAmount, totalQuantity }
}
