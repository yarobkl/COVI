import { supabase } from './supabase'
import { localDay, localMonth } from './dates'
import type { TablesInsert, TablesUpdate } from './database.types'
import type { Arrival, ArrivalKind } from './types'

// Arrival rows are cast to `Arrival`: `kind` is narrowed to the values allowed by its CHECK
// constraint (see types.ts), the generated types only know it as a string.

/** Fields of a new arrival (the shop is given separately). */
export type ArrivalInput = Omit<TablesInsert<'arrivals'>, 'shop_id' | 'kind'> & {
  kind: ArrivalKind
}
export type ExpenseInput = Pick<
  TablesInsert<'shop_expenses'>,
  'category' | 'label' | 'amount' | 'expense_date' | 'recurring'
>
export async function listArrivals(shopId: string) {
  const { data, error } = await supabase
    .from('arrivals')
    .select('*')
    .eq('shop_id', shopId)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as Arrival[]
}
export async function createArrival(shopId: string, input: ArrivalInput) {
  const { data, error } = await supabase
    .from('arrivals')
    .insert({ shop_id: shopId, ...input })
    .select()
    .single()
  if (error) throw error
  return data as Arrival
}
export async function updateArrival(shopId: string, id: string, input: TablesUpdate<'arrivals'>) {
  const { data, error } = await supabase
    .from('arrivals')
    .update(input)
    .eq('shop_id', shopId)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as Arrival
}
export async function listExpenses(shopId: string) {
  const { data, error } = await supabase
    .from('shop_expenses')
    .select('*')
    .eq('shop_id', shopId)
    .order('expense_date', { ascending: false })
  if (error) throw error
  return data ?? []
}
export async function createExpense(shopId: string, input: ExpenseInput) {
  const { data, error } = await supabase
    .from('shop_expenses')
    .insert({ shop_id: shopId, ...input })
    .select()
    .single()
  if (error) throw error
  return data
}
export async function updateExpense(shopId: string, id: string, input: ExpenseInput) {
  const { data, error } = await supabase
    .from('shop_expenses')
    .update(input)
    .eq('shop_id', shopId)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data
}
export async function deleteExpense(shopId: string, id: string) {
  const { error } = await supabase.from('shop_expenses').delete().eq('shop_id', shopId).eq('id', id)
  if (error) throw error
}
/** Today's real sales (examples excluded): how many and how much, from local midnight. */
export async function todaySales(shopId: string) {
  const now = new Date(),
    today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const { data, error } = await supabase
    .from('sales')
    .select('total_amount')
    .eq('shop_id', shopId)
    .eq('is_test', false)
    .gte('sold_at', today.toISOString())
  if (error) throw error
  return {
    count: (data ?? []).length,
    total: (data ?? []).reduce((a, x) => a + Number(x.total_amount), 0),
  }
}

/** Sales by payment method, largest first: « Espèces 74 000 · Mobile Money 52 000 ». */
export function byPaymentMethod(sales: { payment_method: string; total_amount: number }[]) {
  const totals = new Map<string, number>()
  for (const s of sales)
    totals.set(s.payment_method, (totals.get(s.payment_method) ?? 0) + Number(s.total_amount))
  return [...totals]
    .map(([method, amount]) => ({ method, amount }))
    .sort((a, b) => b.amount - a.amount)
}

/** Month expenses grouped by category, largest first. */
export function byCategory(expenses: { category: string; amount: number }[]) {
  const totals = new Map<string, number>()
  for (const e of expenses) totals.set(e.category, (totals.get(e.category) ?? 0) + Number(e.amount))
  return [...totals]
    .map(([category, amount]) => ({ category, amount }))
    .sort((a, b) => b.amount - a.amount)
}

/**
 * Accueil: today (amount, number of sales, split by payment method), the month in notebook lines
 * (sales, charges by category, what is left after charges), last month for comparison, what to
 * follow (arrivals not received yet, low stock) and the last sales. Examples (is_test) excluded.
 */
export async function dashboard(shopId: string) {
  const now = new Date(),
    start = new Date(now.getFullYear(), now.getMonth(), 1),
    previousStart = new Date(now.getFullYear(), now.getMonth() - 1, 1),
    today = new Date(now.getFullYear(), now.getMonth(), now.getDate()),
    [sales, recent, products, expenses, activeArrivals] = await Promise.all([
      supabase
        .from('sales')
        .select('total_amount,sold_at,payment_method')
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .gte('sold_at', previousStart.toISOString()),
      supabase
        .from('sales')
        .select(
          'id,sold_at,payment_method,total_amount,sale_items(quantity,sold_unit_price,products(name,is_unique_piece,arrivals(code,kind)))',
        )
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .order('sold_at', { ascending: false })
        .limit(4),
      supabase
        .from('products')
        .select('id,name,quantity_on_hand,is_unique_piece')
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .eq('status', 'active'),
      supabase
        .from('shop_expenses')
        .select('category,amount,expense_date')
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .gte('expense_date', localDay(start)),
      supabase
        .from('arrivals')
        .select('id,code,kind,status,origin_country,order_date')
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .in('status', ['draft', 'ordered', 'in_transit'])
        .order('created_at', { ascending: false }),
    ])
  for (const r of [sales, recent, products, expenses, activeArrivals]) if (r.error) throw r.error
  const all = sales.data ?? [],
    month = all.filter((x) => new Date(x.sold_at) >= start),
    previous = all.filter((x) => new Date(x.sold_at) < start),
    todays = month.filter((x) => new Date(x.sold_at) >= today),
    sum = (rows: { total_amount: number }[]) =>
      rows.reduce((a, x) => a + Number(x.total_amount), 0),
    charges = (expenses.data ?? []).reduce((a, x) => a + Number(x.amount), 0),
    stockRows = products.data ?? []
  return {
    today: { total: sum(todays), count: todays.length, byMethod: byPaymentMethod(todays) },
    month: {
      total: sum(month),
      count: month.length,
      charges,
      expenses: byCategory(expenses.data ?? []),
      /** Sales minus charges: what the articles cost is not counted. */
      restAfterCharges: sum(month) - charges,
    },
    previousMonth: { total: sum(previous), date: previousStart },
    stock: stockRows.reduce((a, x) => a + Number(x.quantity_on_hand), 0),
    /** Models (not unique pieces) with 2 or fewer left. */
    lowStock: stockRows
      .filter((x) => !x.is_unique_piece && x.quantity_on_hand > 0 && x.quantity_on_hand <= 2)
      .sort((a, b) => a.quantity_on_hand - b.quantity_on_hand),
    arrivalsInProgress: (activeArrivals.data ?? []).map((x) => ({
      ...x,
      kind: x.kind as ArrivalKind,
    })),
    recentSales: (recent.data ?? []).map((s) => ({
      id: s.id,
      soldAt: s.sold_at,
      paymentMethod: s.payment_method,
      total: Number(s.total_amount),
      lines: (s.sale_items ?? []).map((i) => ({
        quantity: Number(i.quantity),
        name: i.products?.name ?? 'Article supprimé',
        balloon: i.products?.arrivals?.kind === 'balloon',
      })),
    })),
  }
}
export type Dashboard = Awaited<ReturnType<typeof dashboard>>

export async function arrivalProfitability(shopId: string) {
  const [a, p, s] = await Promise.all([
    supabase
      .from('arrivals')
      .select('*')
      .eq('shop_id', shopId)
      .order('created_at', { ascending: false }),
    supabase
      .from('products')
      .select(
        'id,arrival_id,name,category,brand,size,initial_sale_price,quantity_on_hand,is_unique_piece,status,is_test',
      )
      .eq('shop_id', shopId),
    supabase
      .from('sales')
      .select(
        'is_test,sale_items(product_id,quantity,sold_unit_price,products(arrival_id,is_test))',
      )
      .eq('shop_id', shopId),
  ])
  for (const r of [a, p, s]) if (r.error) throw r.error
  return ((a.data ?? []) as Arrival[]).map((x) => {
    const products = (p.data ?? []).filter((v) => v.arrival_id === x.id),
      items = (s.data ?? [])
        .flatMap((v) => v.sale_items ?? [])
        .filter((v) => v.products?.arrival_id === x.id)
    const revenue = items.reduce((n, v) => n + Number(v.sold_unit_price) * Number(v.quantity), 0),
      computedCost =
        Number(x.merchandise_cost || 0) +
        Number(x.transport_cost || 0) +
        Number(x.customs_cost || 0),
      cost = Number(x.global_cost) || computedCost,
      sold = items.reduce((n, v) => n + Number(v.quantity), 0),
      remaining = products.reduce((n, v) => n + Number(v.quantity_on_hand), 0)
    return {
      id: x.id,
      code: x.code,
      kind: x.kind,
      origin: x.origin_country,
      supplier: x.supplier_name,
      status: x.status,
      is_test: x.is_test,
      cost,
      revenue,
      profit: revenue - cost,
      recovery: cost > 0 ? Math.round((revenue / cost) * 100) : 0,
      sold,
      remaining,
      productCount: products.length,
      products,
    }
  })
}
export type ArrivalProfit = Awaited<ReturnType<typeof arrivalProfitability>>[number]
export async function liveStatistics(shopId: string) {
  const [sales, products, profit] = await Promise.all([
    supabase
      .from('sales')
      .select('total_amount,sold_at,sale_items(quantity,sold_unit_price,products(category))')
      .eq('shop_id', shopId)
      .order('sold_at', { ascending: true }),
    supabase.from('products').select('category,quantity_on_hand').eq('shop_id', shopId),
    arrivalProfitability(shopId),
  ])
  for (const r of [sales, products]) if (r.error) throw r.error
  const now = new Date(),
    months = Array.from({ length: 3 }, (_, i) => {
      const d = new Date(now.getFullYear(), now.getMonth() - 3 + i, 1)
      return {
        date: localMonth(d),
        label: d.toLocaleDateString('fr-FR', { month: 'short' }),
        amount: 0,
      }
    })
  for (const s of sales.data ?? []) {
    const key = localMonth(new Date(s.sold_at)),
      month = months.find((x) => x.date === key)
    if (month) month.amount += Number(s.total_amount)
  }
  const cats = new Map<string, number>()
  for (const s of sales.data ?? []) {
    if (!months.some((x) => x.date === localMonth(new Date(s.sold_at)))) continue
    for (const i of s.sale_items ?? []) {
      const k = i.products?.category || 'Autre'
      cats.set(k, (cats.get(k) || 0) + Number(i.quantity))
    }
  }
  return { days: months, categories: [...cats].sort((a, b) => b[1] - a[1]).slice(0, 5), profit }
}
