import type { addProduct } from '../../lib/covi'
import type { ArrivalInput } from '../../lib/operations'
import type { Arrival, ArrivalKind } from '../../lib/types'

/** Short random arrival code, e.g. `CMD-1A2B3C`. */
export const arrivalCode = (prefix: string) =>
  prefix + '-' + crypto.randomUUID().slice(0, 6).toUpperCase()

/**
 * New draft arrival from the ArrivalForm fields. A supplier order costs the sum of its goods,
 * transport and customs; a balloon keeps a single global cost.
 */
export function arrivalFromForm(f: FormData, kind: ArrivalKind): ArrivalInput {
  const goods = Number(f.get('goods') || 0),
    transport = Number(f.get('transport') || 0),
    customs = Number(f.get('customs') || 0),
    global = kind === 'balloon' ? Number(f.get('global') || 0) : goods + transport + customs
  return {
    code: arrivalCode(kind === 'balloon' ? 'BAL' : 'CMD'),
    kind,
    origin_country: String(f.get('country') || ''),
    supplier_name: kind === 'supplier_order' ? String(f.get('supplier') || '') : null,
    merchandise_cost: goods,
    transport_cost: transport,
    customs_cost: customs,
    global_cost: global,
    order_date: kind === 'supplier_order' ? String(f.get('orderDate') || '') || null : null,
    received_date: null,
    status: 'draft',
  }
}

/** Product from the ArrivalProductForm fields: a balloon piece is unique, quantity 1. */
export function arrivalProductFromForm(
  f: FormData,
  arrival: Arrival,
): Parameters<typeof addProduct>[1] {
  const unique = arrival.kind === 'balloon',
    qty = unique ? 1 : Math.max(1, Number(f.get('quantity') || 1))
  return {
    arrival_id: arrival.id,
    is_test: arrival.is_test ?? false,
    name: String(f.get('name') || ''),
    category: String(f.get('category') || ''),
    brand: String(f.get('brand') || ''),
    size: String(f.get('size') || ''),
    initial_sale_price: Number(f.get('price') || 0),
    quantity_on_hand: qty,
    is_unique_piece: unique,
    image: (f.get('image') as File)?.size ? (f.get('image') as File) : null,
  }
}
