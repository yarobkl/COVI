// The two arrival forms without their interface: what was typed becomes the arrival to save, or
// the messages to show under the fields.
import { businessErrorMessage } from '../../lib/businessErrors'
import { parseAmount } from '../../lib/format'
import type { ArrivalInput } from '../../lib/operations'

export type OrderValues = {
  country: string
  supplier: string
  /** `YYYY-MM-DD` (date field), may be empty. */
  orderDate: string
  goods: string
  transport: string
  customs: string
}
export type OrderErrors = Partial<Record<'country' | 'supplier' | 'orderDate' | 'goods', string>>

export type BalloonValues = {
  /** Country or place where it was bought (« Brazzaville, marché Total »), may be empty. */
  place: string
  price: string
  /** « Je l’ai déjà reçu »: bought on the spot, its pieces can be added right away. */
  received: boolean
}
export type BalloonErrors = Partial<Record<'price', string>>

type Result<E> = { input: ArrivalInput; errors: null } | { input: null; errors: E }

/** What an order cost: goods + transport + customs. */
export const orderTotal = (v: Pick<OrderValues, 'goods' | 'transport' | 'customs'>) =>
  (parseAmount(v.goods) ?? 0) + (parseAmount(v.transport) ?? 0) + (parseAmount(v.customs) ?? 0)

/**
 * A supplier order, saved as « à commander » (draft): its cost is the sum of the goods, transport
 * and customs. `today` (`YYYY-MM-DD`, local day) refuses an order date in the future.
 */
export function orderFromValues(v: OrderValues, code: string, today: string): Result<OrderErrors> {
  const errors: OrderErrors = {}
  const goods = parseAmount(v.goods) ?? 0
  const transport = parseAmount(v.transport) ?? 0
  const customs = parseAmount(v.customs) ?? 0
  if (!v.country.trim()) errors.country = 'Indiquez le pays d’où vient la marchandise.'
  if (!v.supplier.trim()) errors.supplier = 'Indiquez le fournisseur : un nom ou son WhatsApp.'
  if (!goods) errors.goods = 'Indiquez le prix de la marchandise, en FCFA.'
  if (v.orderDate && v.orderDate > today)
    errors.orderDate = 'Cette date n’est pas encore passée. Indiquez le jour de la commande.'
  if (Object.keys(errors).length) return { input: null, errors }
  return {
    errors: null,
    input: {
      code,
      kind: 'supplier_order',
      origin_country: v.country.trim(),
      supplier_name: v.supplier.trim(),
      merchandise_cost: goods,
      transport_cost: transport,
      customs_cost: customs,
      global_cost: goods + transport + customs,
      order_date: v.orderDate || null,
      received_date: null,
      status: 'draft',
    },
  }
}

/**
 * A bale keeps one global cost (never a price per piece). Bought on the spot (« Je l’ai déjà
 * reçu »), it is saved received today, so its pieces can be added at once; otherwise it is paid
 * and waits (« commandé »). It has no order date: the database accepts a received date alone.
 */
export function balloonFromValues(
  v: BalloonValues,
  code: string,
  today: string,
): Result<BalloonErrors> {
  const price = parseAmount(v.price) ?? 0
  if (!price) return { input: null, errors: { price: 'Indiquez le prix payé pour le ballon.' } }
  return {
    errors: null,
    input: {
      code,
      kind: 'balloon',
      origin_country: v.place.trim() || null,
      supplier_name: null,
      merchandise_cost: 0,
      transport_cost: 0,
      customs_cost: 0,
      global_cost: price,
      order_date: null,
      received_date: v.received ? today : null,
      status: v.received ? 'received' : 'ordered',
    },
  }
}

const textOf = (error: unknown) => {
  const e = error as { message?: unknown; code?: unknown } | null | undefined
  return { message: String(e?.message ?? error ?? '').toLowerCase(), code: String(e?.code ?? '') }
}

/** The code is already taken (unique (shop_id, code)): another one is tried. */
export const isCodeTaken = (error: unknown) => {
  const { message, code } = textOf(error)
  return code === '23505' || message.includes('arrivals_shop_id_code_key')
}

/** What to tell when saving an arrival (or its step) fails: never English or technical. */
export function arrivalSaveError(error: unknown): string {
  const { message } = textOf(error)
  if (message.includes('arrivals_dates_check'))
    return 'La réception ne peut pas être datée avant la commande. Vérifiez la date de commande.'
  const business = businessErrorMessage(error)
  if (business) return business
  if (typeof navigator !== 'undefined' && !navigator.onLine)
    return 'Pas de réseau : rien n’est enregistré. Réessayez quand le réseau revient.'
  if (message.includes('failed to fetch') || message.includes('network'))
    return 'Pas de réseau : rien n’est enregistré. Réessayez quand le réseau revient.'
  return 'Ça n’a pas marché. Vérifiez le réseau puis réessayez.'
}
