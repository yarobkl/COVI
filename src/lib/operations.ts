import { supabase } from './supabase'
import { localDay, localMonth } from './dates'
export type Arrival = {
  id: string
  code: string
  kind: 'supplier_order' | 'balloon'
  origin_country: string | null
  supplier_name: string | null
  order_date: string | null
  received_date: string | null
  merchandise_cost: number
  transport_cost: number
  customs_cost: number
  global_cost: number
  status: string
  is_test?: boolean
}
export type Expense = {
  id: string
  category: string
  label: string | null
  amount: number
  expense_date: string
  recurring: boolean
  is_test?: boolean
}
export async function listArrivals(shopId: string) {
  const { data, error } = await supabase
    .from('arrivals')
    .select('*')
    .eq('shop_id', shopId)
    .order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as Arrival[]
}
export async function createArrival(shopId: string, input: Partial<Arrival>) {
  const { data, error } = await supabase
    .from('arrivals')
    .insert({ shop_id: shopId, ...input })
    .select()
    .single()
  if (error) throw error
  return data as Arrival
}
export async function updateArrival(shopId: string, id: string, input: Partial<Arrival>) {
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
  return (data ?? []) as Expense[]
}
export async function createExpense(
  shopId: string,
  input: {
    category: string
    label?: string
    amount: number
    expense_date: string
    recurring: boolean
  },
) {
  const { data, error } = await supabase
    .from('shop_expenses')
    .insert({ shop_id: shopId, ...input })
    .select()
    .single()
  if (error) throw error
  return data as Expense
}
export async function updateExpense(
  shopId: string,
  id: string,
  input: {
    category: string
    label?: string
    amount: number
    expense_date: string
    recurring: boolean
  },
) {
  const { data, error } = await supabase
    .from('shop_expenses')
    .update(input)
    .eq('shop_id', shopId)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as Expense
}
export async function deleteExpense(shopId: string, id: string) {
  const { error } = await supabase.from('shop_expenses').delete().eq('shop_id', shopId).eq('id', id)
  if (error) throw error
}
export async function dashboard(shopId: string) {
  const now = new Date(),
    start = new Date(now.getFullYear(), now.getMonth(), 1),
    today = new Date(now.getFullYear(), now.getMonth(), now.getDate()),
    [sales, products, expenses, arrivals, activeArrivals] = await Promise.all([
      supabase
        .from('sales')
        .select('total_amount,sold_at')
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .gte('sold_at', start.toISOString()),
      supabase
        .from('products')
        .select('quantity_on_hand,status')
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .eq('status', 'active'),
      supabase
        .from('shop_expenses')
        .select('amount,expense_date')
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .gte('expense_date', localDay(start)),
      supabase
        .from('arrivals')
        .select('global_cost,merchandise_cost,transport_cost,customs_cost,received_date,status')
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .gte('received_date', localDay(start))
        .eq('status', 'received'),
      supabase
        .from('arrivals')
        .select('kind,status')
        .eq('shop_id', shopId)
        .eq('is_test', false)
        .in('status', ['draft', 'ordered', 'in_transit']),
    ])
  for (const r of [sales, products, expenses, arrivals, activeArrivals]) if (r.error) throw r.error
  const monthSales = (sales.data ?? []).reduce((a, x) => a + Number(x.total_amount), 0),
    todaySales = (sales.data ?? [])
      .filter((x) => new Date(x.sold_at) >= today)
      .reduce((a, x) => a + Number(x.total_amount), 0),
    charges = (expenses.data ?? []).reduce((a, x) => a + Number(x.amount), 0),
    arrivalCost = (arrivals.data ?? []).reduce(
      (a, x) =>
        a +
        Number(
          x.global_cost ||
            Number(x.merchandise_cost) + Number(x.transport_cost) + Number(x.customs_cost),
        ),
      0,
    ),
    stock = (products.data ?? []).reduce((a, x) => a + Number(x.quantity_on_hand), 0)
  return {
    todaySales,
    monthSales,
    charges,
    arrivalCost,
    stock,
    profitBeforeCharges: monthSales - arrivalCost,
    profit: monthSales - arrivalCost - charges,
    saleCount: (sales.data ?? []).length,
    arrivalsInProgress: (activeArrivals.data ?? []).length,
    ordersInProgress: (activeArrivals.data ?? []).filter((x) => x.kind === 'supplier_order').length,
    balloonsInProgress: (activeArrivals.data ?? []).filter((x) => x.kind === 'balloon').length,
  }
}

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
  return (a.data ?? []).map((x: any) => {
    const products = (p.data ?? []).filter((v: any) => v.arrival_id === x.id),
      items = (s.data ?? [])
        .flatMap((v: any) => v.sale_items ?? [])
        .filter((v: any) => v.products?.arrival_id === x.id)
    const revenue = items.reduce(
        (n: number, v: any) => n + Number(v.sold_unit_price) * Number(v.quantity),
        0,
      ),
      computedCost =
        Number(x.merchandise_cost || 0) +
        Number(x.transport_cost || 0) +
        Number(x.customs_cost || 0),
      cost = Number(x.global_cost) || computedCost,
      sold = items.reduce((n: number, v: any) => n + Number(v.quantity), 0),
      remaining = products.reduce((n: number, v: any) => n + Number(v.quantity_on_hand), 0)
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
      const k = (i.products as any)?.category || 'Autre'
      cats.set(k, (cats.get(k) || 0) + Number(i.quantity))
    }
  }
  return { days: months, categories: [...cats].sort((a, b) => b[1] - a[1]).slice(0, 5), profit }
}
