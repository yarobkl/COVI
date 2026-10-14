// « Ventes par caissier » : regroupement des ventes par vendeur (sales.seller_id).
import type { Sale } from '../../lib/types'

/** Seller filter: everybody, the owner (sales without a cashier), or one cashier's user id. */
export const ALL = 'tous'
export const OWNER = 'responsable'

export type SellerTotal = { key: string; name: string; count: number; total: number }

/** The owner's own sales and the sales recorded before the team share one line. */
export const sellerKey = (sellerId: string | null, ownerId: string | null) =>
  !sellerId || sellerId === ownerId ? OWNER : sellerId

/**
 * Sales per seller: the owner (their own sales and sales recorded before the team existed) and
 * each cashier, most sold first.
 */
export function sellerTotals(
  sales: Pick<Sale, 'seller_id' | 'total_amount' | 'is_test'>[],
  ownerId: string | null,
  names: Map<string, string>,
): SellerTotal[] {
  const byKey = new Map<string, SellerTotal>()
  for (const s of sales) {
    if (s.is_test) continue
    const key = sellerKey(s.seller_id, ownerId)
    const name = key === OWNER ? 'Vous (responsable)' : (names.get(key) ?? 'Ancien caissier')
    const row = byKey.get(key) ?? { key, name, count: 0, total: 0 }
    row.count += 1
    row.total += Number(s.total_amount)
    byKey.set(key, row)
  }
  return [...byKey.values()].sort((a, b) => b.total - a.total || a.name.localeCompare(b.name))
}
