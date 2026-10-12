import { supabase } from './supabase'

/** This module is not wired to the current SalePage.
 * The future RPCs require isolated DB testing before first use.
 */
export type ManualOrderLineInput = {
  categoryId: string
  quantity: number
  negotiatedUnitPriceXaf: number
}

export type ManualOrderLine = {
  categoryId: string
  quantity: number
  unitPriceXaf: number
}

export type ManualOrderRequest = {
  shopId: string
  operationId: string
  lines: readonly ManualOrderLineInput[]
  isTest: boolean
  customerPhone?: string
  customerNote?: string
  fulfillment: 'pickup' | 'delivery'
}

export type RecordedManualOrder = {
  orderId: string
  status: 'submitted' | 'approved' | 'reserved' | 'paid' | 'cancelled' | 'expired'
  amountXaf: number
}

type RpcResult = { data: unknown; error: { message: string } | null }
type FutureOrderRpc = {
  rpc: (
    name: 'create_manual_checkout_order' | 'approve_manual_checkout_order',
    args: Record<string, unknown>,
  ) => PromiseLike<RpcResult>
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const MAX_XAF = 9_000_000_000_000
const MAX_QTY = 2_147_483_647

function containsAsciiControl(value: string): boolean {
  return Array.from(value).some((character) => {
    const point = character.codePointAt(0)
    return point !== undefined && (point < 32 || point === 127)
  })
}

export function prepareManualOrderLines(
  lines: readonly ManualOrderLineInput[],
): { lines: ManualOrderLine[]; amountXaf: number } {
  if (lines.length < 1 || lines.length > 100)
    throw new Error('Une commande contient entre 1 et 100 lignes.')
  const grouped = new Map<string, ManualOrderLine>()
  const quantityByCategory = new Map<string, number>()
  let amountXaf = 0
  for (const item of lines) {
    if (!UUID.test(item.categoryId))
      throw new Error('Catégorie de stock invalide.')
    if (!Number.isSafeInteger(item.quantity) || item.quantity < 1 || item.quantity > MAX_QTY)
      throw new Error('Quantité invalide.')
    if (!Number.isSafeInteger(item.negotiatedUnitPriceXaf) ||
        item.negotiatedUnitPriceXaf < 0 || item.negotiatedUnitPriceXaf > MAX_XAF)
      throw new Error('Prix négocié invalide.')

    const lineTotal = item.quantity * item.negotiatedUnitPriceXaf
    if (!Number.isSafeInteger(lineTotal) || lineTotal > MAX_XAF)
      throw new Error('Montant de ligne trop élevé.')
    amountXaf += lineTotal
    if (!Number.isSafeInteger(amountXaf) || amountXaf > MAX_XAF)
      throw new Error('Montant total trop élevé.')

    const categoryId = item.categoryId.toLowerCase()
    const categoryQuantity = (quantityByCategory.get(categoryId) ?? 0) + item.quantity
    if (categoryQuantity > MAX_QTY)
      throw new Error('Quantité de catégorie trop élevée.')
    quantityByCategory.set(categoryId, categoryQuantity)

    const key = categoryId + ':' + item.negotiatedUnitPriceXaf
    const existing = grouped.get(key)
    if (existing) {
      existing.quantity += item.quantity
    } else {
      grouped.set(key, {
        categoryId,
        quantity: item.quantity,
        unitPriceXaf: item.negotiatedUnitPriceXaf,
      })
    }
  }
  const prepared = Array.from(grouped.values()).sort(
    (a, b) => a.categoryId.localeCompare(b.categoryId) ||
      a.unitPriceXaf - b.unitPriceXaf,
  )
  return { lines: prepared, amountXaf }
}

export function prepareManualOrderRequest(input: ManualOrderRequest) {
  if (!UUID.test(input.shopId) || !UUID.test(input.operationId))
    throw new Error('Boutique ou identifiant de commande invalide.')
  if (typeof input.isTest !== 'boolean' ||
      (input.fulfillment !== 'pickup' && input.fulfillment !== 'delivery'))
    throw new Error('Paramètres de commande invalides.')
  const customerPhone = input.customerPhone?.trim() || null
  const customerNote = input.customerNote?.trim() || null
  if ((customerPhone && (customerPhone.length > 32 || containsAsciiControl(customerPhone))) ||
      (customerNote && (customerNote.length > 500 || containsAsciiControl(customerNote))))
    throw new Error('Coordonnées ou note trop longues ou invalides.')
  const prepared = prepareManualOrderLines(input.lines)
  return {
    p_shop_id: input.shopId,
    p_operation_id: input.operationId,
    p_lines: prepared.lines,
    p_is_test: input.isTest,
    p_customer_phone: customerPhone,
    p_customer_note: customerNote,
    p_fulfillment: input.fulfillment,
  }
}

export function parseRecordedManualOrder(data: unknown): RecordedManualOrder {
  if (!data || typeof data !== 'object' || Array.isArray(data))
    throw new Error('Réponse de commande invalide.')
  const row = data as Record<string, unknown>
  if (typeof row.orderId !== 'string' || !UUID.test(row.orderId) ||
      !['submitted', 'approved', 'reserved', 'paid', 'cancelled', 'expired'].includes(String(row.status)) ||
      !Number.isSafeInteger(row.amountXaf) ||
      (row.amountXaf as number) < 0 || (row.amountXaf as number) > MAX_XAF)
    throw new Error('Réponse de commande invalide.')
  return {
    orderId: row.orderId,
    status: row.status as RecordedManualOrder['status'],
    amountXaf: row.amountXaf as number,
  }
}

export async function createManualCheckoutOrder(
  input: ManualOrderRequest,
): Promise<RecordedManualOrder> {
  const args = prepareManualOrderRequest(input)
  const client = supabase as unknown as FutureOrderRpc
  const { data, error } = await client.rpc('create_manual_checkout_order', args)
  if (error) throw new Error(error.message)
  return parseRecordedManualOrder(data)
}

export async function approveManualCheckoutOrder(input: {
  shopId: string
  orderId: string
}): Promise<RecordedManualOrder> {
  if (!UUID.test(input.shopId) || !UUID.test(input.orderId))
    throw new Error('Identifiants de commande invalides.')
  const client = supabase as unknown as FutureOrderRpc
  const { data, error } = await client.rpc('approve_manual_checkout_order', {
    p_shop_id: input.shopId,
    p_order_id: input.orderId,
  })
  if (error) throw new Error(error.message)
  const order = parseRecordedManualOrder(data)
  if (order.status !== 'approved') throw new Error('Commande non approuvée.')
  return order
}
