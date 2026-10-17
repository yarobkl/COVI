import { supabase } from './supabase'

/** Dedicated category-only inventory. Never fall back to legacy SKU/products. */
export type CheckoutStockCategory = {
  id: string
  shopId: string
  label: string
  available: number
  isTest: boolean
}

type QueryResult = { data: unknown; error: { message: string } | null }
type StockQuery = {
  eq: (column: string, value: string | boolean) => StockQuery
  order: (column: string, options: { ascending: boolean }) => PromiseLike<QueryResult>
}
type FutureStockClient = {
  from: (table: 'stock_categories') => { select: (fields: string) => StockQuery }
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

export function parseCheckoutStockCategories(
  raw: unknown,
  shopId: string,
  isTest: boolean,
): CheckoutStockCategory[] {
  if (!Array.isArray(raw)) throw new Error('Liste du stock par catégories invalide.')
  const ids = new Set<string>()
  const result: CheckoutStockCategory[] = []
  for (const item of raw) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) {
      throw new Error('Ligne de stock invalide.')
    }
    const row = item as Record<string, unknown>
    if (
      typeof row.id !== 'string' ||
      !UUID.test(row.id) ||
      row.shop_id !== shopId ||
      row.is_test !== isTest ||
      typeof row.display_name !== 'string' ||
      !row.display_name.trim() ||
      !Number.isSafeInteger(row.quantity_on_hand) ||
      !Number.isSafeInteger(row.quantity_reserved)
    ) {
      throw new Error('Ligne de stock invalide.')
    }
    const quantity = row.quantity_on_hand as number
    const reserved = row.quantity_reserved as number
    if (quantity < 0 || reserved < 0 || reserved > quantity || ids.has(row.id)) {
      throw new Error('Quantités du stock incohérentes.')
    }
    ids.add(row.id)
    result.push({
      id: row.id,
      shopId,
      label: row.display_name.trim(),
      available: quantity - reserved,
      isTest,
    })
  }
  return result.sort((a, b) => a.label.localeCompare(b.label, 'fr'))
}

/**
 * Prepared read-only query for the future category-stock rollout.
 * This function is not used on the current production routes and does not
 * query/transform the legacy product catalog or a customer's public order.
 */
export async function listCheckoutStockCategories(
  shopId: string,
  isTest: boolean,
): Promise<CheckoutStockCategory[]> {
  if (!UUID.test(shopId) || typeof isTest !== 'boolean')
    throw new Error('Boutique ou type de stock invalide.')
  const client = supabase as unknown as FutureStockClient
  const { data, error } = await client
    .from('stock_categories')
    .select('id,shop_id,display_name,quantity_on_hand,quantity_reserved,is_test')
    .eq('shop_id', shopId)
    .eq('is_test', isTest)
    .order('display_name', { ascending: true })
  if (error) throw new Error(error.message)
  return parseCheckoutStockCategories(data, shopId, isTest)
}
