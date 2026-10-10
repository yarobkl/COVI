// Counter arithmetic of the sale screen, kept apart from the components to be tested.
import type { Product } from '../../lib/types'

/** Discount granted on the whole sale (displayed price × quantity − sold price × quantity). */
export const discountOf = (displayed: number, sold: number, quantity = 1) =>
  Math.max(0, (displayed - sold) * quantity)

/** Change to give back for a cash payment (display only, never stored). */
export type CashChange =
  | { kind: 'none' }
  | { kind: 'short'; amount: number }
  | { kind: 'exact' }
  | { kind: 'change'; amount: number }

export function cashChange(total: number, received: number | null): CashChange {
  if (received === null || received <= 0) return { kind: 'none' }
  if (received < total) return { kind: 'short', amount: total - received }
  if (received === total) return { kind: 'exact' }
  return { kind: 'change', amount: received - total }
}

/**
 * Notes the customer is likely to hand over for `total`: the exact amount first (« Compte
 * juste »), then the next round amounts (5 000, 10 000…), three choices at most after it.
 */
export function cashSuggestions(total: number): number[] {
  if (total <= 0) return []
  const up = (step: number) => Math.ceil(total / step) * step
  const candidates = [total, up(1000), up(5000), up(10000), up(10000) + 10000]
  return [...new Set(candidates)].filter((x) => x >= total).slice(0, 4)
}

/** A price far under the displayed one (< 50 %) is checked gently before validating. */
export const isFarBelow = (displayed: number, sold: number) =>
  displayed > 0 && sold < displayed * 0.5

/** Lower case without accents, for searching « chemise » in « Chemisé »… */
export const normalize = (text: string) =>
  text.normalize('NFD').replace(/\p{M}/gu, '').toLowerCase().trim()

/** The product matches every word typed (name, brand, type, size or arrival code). */
export function matchesSearch(product: Product, arrivalCode: string | undefined, query: string) {
  const words = normalize(query).split(/\s+/).filter(Boolean)
  if (!words.length) return true
  const haystack = normalize(
    [product.name, product.brand, product.category, product.size, arrivalCode]
      .filter(Boolean)
      .join(' '),
  )
  return words.every((w) => haystack.includes(w))
}

/** Stock shown on a tile: « Pièce unique », « Restent 3 », « Plus que 1 » (low), « Épuisé ». */
export function stockNote(product: Pick<Product, 'quantity_on_hand' | 'is_unique_piece'>): {
  text: string
  low: boolean
  out: boolean
} {
  const q = Number(product.quantity_on_hand)
  if (q <= 0) return { text: 'Épuisé', low: false, out: true }
  if (product.is_unique_piece) return { text: 'Pièce unique', low: false, out: false }
  if (q <= 2) return { text: `Plus que ${q}`, low: true, out: false }
  return { text: `Restent ${q}`, low: false, out: false }
}
