import { supabase } from './supabase'
import { categoryCheckoutEnabled } from './checkoutFeatureFlag'

/** Category-only receipts are kept separate from legacy product sale_items. */
export type CategorySaleHistory = {
  saleId: string
  receiptNumber: string
  confirmedAt: string
  cashierFirstName: string
  method: 'cash' | 'mobile_money' | 'other'
  amountXaf: number
  isTest: boolean
  lines: Array<{ label: string; quantity: number; lineTotalXaf: number }>
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function object(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value))
    throw new Error('Historique des ventes par catégorie invalide.')
  return value as Record<string, unknown>
}

export function parseCategorySaleHistory(data: unknown): CategorySaleHistory[] {
  if (!Array.isArray(data) || data.length > 500)
    throw new Error('Historique des ventes par catégorie invalide.')
  const ids = new Set<string>()
  return data.map((value) => {
    const r = object(value)
    if (
      typeof r.sale_id !== 'string' ||
      !UUID.test(r.sale_id) ||
      ids.has(r.sale_id) ||
      typeof r.receipt_number !== 'string' ||
      !/^CV-(?:TEST-)?[0-9]{4}-[0-9]{6,}$/.test(r.receipt_number) ||
      typeof r.confirmed_at !== 'string' ||
      !Number.isFinite(Date.parse(r.confirmed_at)) ||
      typeof r.cashier_first_name !== 'string' ||
      !r.cashier_first_name.trim() ||
      !['cash', 'mobile_money', 'other'].includes(String(r.method)) ||
      !Number.isSafeInteger(r.amount_xaf) ||
      (r.amount_xaf as number) < 0 ||
      !Array.isArray(r.receipt_lines) ||
      r.receipt_lines.length < 1
    ) {
      throw new Error('Reçu de catégorie incomplet ou incorrect.')
    }
    ids.add(r.sale_id)
    let total = 0
    const lines = r.receipt_lines.map((value: unknown) => {
      const line = object(value)
      if (
        typeof line.label !== 'string' ||
        !line.label.trim() ||
        !Number.isSafeInteger(line.quantity) ||
        (line.quantity as number) < 1 ||
        !Number.isSafeInteger(line.lineTotalXaf) ||
        (line.lineTotalXaf as number) < 0
      ) {
        throw new Error('Ligne du reçu de catégorie incorrecte.')
      }
      total += line.lineTotalXaf as number
      if (!Number.isSafeInteger(total)) throw new Error('Montant du reçu trop élevé.')
      return {
        label: line.label.trim(),
        quantity: line.quantity as number,
        lineTotalXaf: line.lineTotalXaf as number,
      }
    })
    if (total !== r.amount_xaf) throw new Error('Montant et lignes du reçu incohérents.')
    return {
      saleId: r.sale_id,
      receiptNumber: r.receipt_number,
      confirmedAt: r.confirmed_at,
      cashierFirstName: r.cashier_first_name.trim(),
      method: r.method as CategorySaleHistory['method'],
      amountXaf: r.amount_xaf as number,
      isTest: r.receipt_number.startsWith('CV-TEST-'),
      lines,
    }
  })
}

type HistoryRpc = {
  from: (table: 'manual_payment_confirmations') => {
    select: (columns: string) => {
      eq: (
        column: string,
        value: string,
      ) => {
        order: (
          column: string,
          options: { ascending: boolean },
        ) => {
          limit: (amount: number) => PromiseLike<{
            data: unknown
            error: { message: string } | null
          }>
        }
      }
    }
  }
}

/** Read-only, owner-RLS-protected receipts; never called on legacy production. */
export async function listCategorySaleHistory(shopId: string, limit = 500) {
  if (!categoryCheckoutEnabled) return []
  if (!UUID.test(shopId) || !Number.isInteger(limit) || limit < 1 || limit > 500)
    throw new Error('Paramètres de l’historique invalides.')
  const client = supabase as unknown as HistoryRpc
  const { data, error } = await client
    .from('manual_payment_confirmations')
    .select(
      'sale_id,receipt_number,confirmed_at,cashier_first_name,method,amount_xaf,receipt_lines',
    )
    .eq('shop_id', shopId)
    .order('confirmed_at', { ascending: false })
    .limit(limit)
  if (error) throw new Error(error.message)
  return parseCategorySaleHistory(data ?? [])
}
