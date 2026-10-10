import { supabase } from './supabase'
import { localDay, localMonth } from './dates'
import { arrivalProfitability, dashboard } from './operations'

// Indicateurs calculés en base (supabase/migrations/20261010090100_shop_aggregates.sql), avec
// repli sur l'ancien calcul dans le navigateur tant que les fonctions SQL ne sont pas appliquées
// en production. Le repli ne se déclenche que si la fonction est absente ; toute autre erreur
// (droits, réseau, boutique inconnue…) est propagée telle quelle.

export const DEFAULT_TIME_ZONE = 'Africa/Brazzaville'

export interface InsightOptions {
  /** Fuseau IANA des bornes « aujourd'hui » et des mois civils (défaut Africa/Brazzaville). */
  timeZone?: string
  /** Inclure les données d'exemple (is_test). Défaut false. */
  includeTest?: boolean
}

/** 'database' : fonction SQL ; 'client' : ancien calcul dans le navigateur (heure de l'appareil). */
export type InsightSource = 'database' | 'client'

export interface PaymentMethodAmount {
  method: string
  amount: number
}
export interface CategoryAmount {
  category: string
  amount: number
}
export interface CategorySales {
  category: string
  quantity: number
  amount: number
}

/** Forme de `shop_dashboard` (montants en FCFA, dates locales 'YYYY-MM-DD'). */
export interface ShopDashboard {
  source: InsightSource
  timeZone: string
  today: string
  monthStart: string
  todaySales: number
  todayCount: number
  todayByPaymentMethod: PaymentMethodAmount[]
  monthSales: number
  saleCount: number
  previousMonthStart: string
  previousMonthSales: number
  charges: number
  expensesByCategory: CategoryAmount[]
  /** monthSales - charges (le coût des articles n'est pas compté). */
  restAfterCharges: number
  /** Coût des arrivages reçus dans le mois. */
  arrivalCost: number
  stock: number
  profitBeforeCharges: number
  profit: number
  arrivalsInProgress: number
  ordersInProgress: number
  balloonsInProgress: number
  inProgressByStatus: { draft: number; ordered: number; in_transit: number }
}

export interface MonthSales {
  /** 'YYYY-MM'. */
  month: string
  /** Premier jour du mois, 'YYYY-MM-DD'. */
  start: string
  amount: number
  saleCount: number
  topCategories: CategorySales[]
}

/** Forme de `shop_monthly_sales` : mois civils complets précédant le mois en cours. */
export interface MonthlySales {
  source: InsightSource
  timeZone: string
  /** Bornes locales [from, to), 'YYYY-MM-DD'. */
  from: string
  to: string
  months: MonthSales[]
  topCategories: CategorySales[]
}

/** Une ligne de `arrival_profitability`, en camelCase. */
export interface ArrivalProfitability {
  arrivalId: string
  code: string
  kind: string
  status: string
  originCountry: string | null
  supplierName: string | null
  /** null dans le calcul de repli (non disponible). */
  orderDate: string | null
  receivedDate: string | null
  isTest: boolean
  cost: number
  revenue: number
  profit: number
  recoveryPercent: number
  remainingToRecover: number
  soldUnits: number
  remainingUnits: number
  productCount: number
}

/** Forme de `shop_estimated_profit` (montants arrondis à 2 décimales). */
export interface EstimatedProfit {
  timeZone: string
  from: string | null
  to: string | null
  revenue: number
  costOfGoodsSold: number
  grossProfit: number
  charges: number
  netProfit: number
  revenueWithoutCost: number
  unsoldStockCost: number
  unallocatedArrivalCost: number
}

type InsightFunction =
  'shop_dashboard' | 'shop_monthly_sales' | 'arrival_profitability' | 'shop_estimated_profit'

// Fonctions absentes de la base, mémorisées pour la session : pas de nouvel appel inutile.
const unavailable = new Set<InsightFunction>()

/** Oublie les fonctions marquées absentes (tests, ou après une mise à jour de la base). */
export function resetInsightsAvailability() {
  unavailable.clear()
}

/** La fonction SQL n'existe pas (encore) : PostgREST PGRST202, Postgres 42883. */
export function isMissingFunctionError(error: unknown) {
  if (!error || typeof error !== 'object') return false
  const { code, message } = error as { code?: unknown; message?: unknown }
  return (
    code === 'PGRST202' ||
    code === '42883' ||
    (typeof message === 'string' && message.includes('Could not find the function'))
  )
}

async function withFallback<T>(
  fn: InsightFunction,
  rpc: () => Promise<T>,
  fallback: () => Promise<T>,
): Promise<T> {
  if (!unavailable.has(fn)) {
    try {
      return await rpc()
    } catch (error) {
      if (!isMissingFunctionError(error)) throw error
      unavailable.add(fn)
    }
  }
  return fallback()
}

function required<T>(data: unknown, fn: InsightFunction): T {
  if (data === null || data === undefined) throw new Error(`${fn} : réponse vide`)
  return data as T
}

const deviceTimeZone = () => Intl.DateTimeFormat().resolvedOptions().timeZone
const firstOfMonth = (d: Date) => `${localMonth(d)}-01`

// Tableau de bord ----------------------------------------------------------------------------

/**
 * `base` : le dashboard() déjà demandé par l'écran (listes de l'accueil), réutilisé par le repli
 * pour ne pas relire les mêmes tables deux fois.
 */
export function fetchShopDashboard(
  shopId: string,
  opts: InsightOptions = {},
  base: () => ReturnType<typeof dashboard> = () => dashboard(shopId),
) {
  return withFallback<ShopDashboard>(
    'shop_dashboard',
    async () => {
      const { data, error } = await supabase.rpc('shop_dashboard', {
        p_shop_id: shopId,
        p_tz: opts.timeZone ?? DEFAULT_TIME_ZONE,
        p_include_test: opts.includeTest ?? false,
      })
      if (error) throw error
      return {
        ...required<Omit<ShopDashboard, 'source'>>(data, 'shop_dashboard'),
        source: 'database',
      }
    },
    () => clientDashboard(shopId, base),
  )
}

/** Repli : dashboard() (heure de l'appareil, exemples exclus) + coût des arrivages reçus. */
async function clientDashboard(
  shopId: string,
  base: () => ReturnType<typeof dashboard>,
): Promise<ShopDashboard> {
  const now = new Date(),
    monthStart = new Date(now.getFullYear(), now.getMonth(), 1),
    nextMonth = new Date(now.getFullYear(), now.getMonth() + 1, 1)
  const [d, received] = await Promise.all([
    base(),
    supabase
      .from('arrivals')
      .select('global_cost,merchandise_cost,transport_cost,customs_cost')
      .eq('shop_id', shopId)
      .eq('is_test', false)
      .eq('status', 'received')
      .gte('received_date', localDay(monthStart))
      .lt('received_date', localDay(nextMonth)),
  ])
  if (received.error) throw received.error
  const arrivalCost = (received.data ?? []).reduce(
      (n, a) =>
        n +
        (Number(a.global_cost) ||
          Number(a.merchandise_cost || 0) +
            Number(a.transport_cost || 0) +
            Number(a.customs_cost || 0)),
      0,
    ),
    inProgress = d.arrivalsInProgress,
    count = (pred: (a: (typeof inProgress)[number]) => boolean) => inProgress.filter(pred).length
  return {
    source: 'client',
    timeZone: deviceTimeZone(),
    today: localDay(now),
    monthStart: localDay(monthStart),
    todaySales: d.today.total,
    todayCount: d.today.count,
    todayByPaymentMethod: d.today.byMethod,
    monthSales: d.month.total,
    saleCount: d.month.count,
    previousMonthStart: localDay(d.previousMonth.date),
    previousMonthSales: d.previousMonth.total,
    charges: d.month.charges,
    expensesByCategory: d.month.expenses,
    restAfterCharges: d.month.restAfterCharges,
    arrivalCost,
    stock: d.stock,
    profitBeforeCharges: d.month.total - arrivalCost,
    profit: d.month.total - arrivalCost - d.month.charges,
    arrivalsInProgress: inProgress.length,
    ordersInProgress: count((a) => a.kind === 'supplier_order'),
    balloonsInProgress: count((a) => a.kind === 'balloon'),
    inProgressByStatus: {
      draft: count((a) => a.status === 'draft'),
      ordered: count((a) => a.status === 'ordered'),
      in_transit: count((a) => a.status === 'in_transit'),
    },
  }
}

// Ventes mensuelles --------------------------------------------------------------------------

export function fetchMonthlySales(shopId: string, months = 3, opts: InsightOptions = {}) {
  return withFallback<MonthlySales>(
    'shop_monthly_sales',
    async () => {
      const { data, error } = await supabase.rpc('shop_monthly_sales', {
        p_shop_id: shopId,
        p_months: months,
        p_tz: opts.timeZone ?? DEFAULT_TIME_ZONE,
        p_include_test: opts.includeTest ?? false,
      })
      if (error) throw error
      return {
        ...required<Omit<MonthlySales, 'source'>>(data, 'shop_monthly_sales'),
        source: 'database',
      }
    },
    () => clientMonthlySales(shopId, months, opts.includeTest ?? false),
  )
}

const byQuantity = (a: CategorySales, b: CategorySales) =>
  b.quantity - a.quantity ||
  b.amount - a.amount ||
  (a.category < b.category ? -1 : a.category > b.category ? 1 : 0)

/** Repli : même calcul que liveStatistics(), généralisé à N mois (heure de l'appareil). */
async function clientMonthlySales(
  shopId: string,
  count: number,
  includeTest: boolean,
): Promise<MonthlySales> {
  if (!Number.isInteger(count) || count < 1 || count > 120)
    throw new Error('p_months must be between 1 and 120')
  const now = new Date(),
    to = new Date(now.getFullYear(), now.getMonth(), 1),
    from = new Date(now.getFullYear(), now.getMonth() - count, 1)
  let query = supabase
    .from('sales')
    .select('total_amount,sold_at,sale_items(quantity,sold_unit_price,products(category))')
    .eq('shop_id', shopId)
    .gte('sold_at', from.toISOString())
    .lt('sold_at', to.toISOString())
  if (!includeTest) query = query.eq('is_test', false)
  const { data, error } = await query
  if (error) throw error

  const months = Array.from({ length: count }, (_, i) => {
      const d = new Date(now.getFullYear(), now.getMonth() - count + i, 1)
      return {
        month: localMonth(d),
        start: firstOfMonth(d),
        amount: 0,
        saleCount: 0,
        cats: new Map<string, CategorySales>(),
      }
    }),
    total = new Map<string, CategorySales>()
  const add = (map: Map<string, CategorySales>, category: string, q: number, amount: number) => {
    const c = map.get(category) ?? { category, quantity: 0, amount: 0 }
    c.quantity += q
    c.amount += amount
    map.set(category, c)
  }
  for (const s of data ?? []) {
    const m = months.find((x) => x.month === localMonth(new Date(s.sold_at)))
    if (!m) continue
    m.amount += Number(s.total_amount)
    m.saleCount += 1
    for (const i of s.sale_items ?? []) {
      const category = (i.products?.category ?? '').trim() || 'Autre',
        q = Number(i.quantity),
        amount = q * Number(i.sold_unit_price)
      add(m.cats, category, q, amount)
      add(total, category, q, amount)
    }
  }
  const top = (map: Map<string, CategorySales>) => [...map.values()].sort(byQuantity).slice(0, 5)
  return {
    source: 'client',
    timeZone: deviceTimeZone(),
    from: localDay(from),
    to: localDay(to),
    months: months.map(({ cats, ...m }) => ({ ...m, topCategories: top(cats) })),
    topCategories: top(total),
  }
}

// Rentabilité par arrivage -------------------------------------------------------------------

export function fetchArrivalProfitability(shopId: string, opts: InsightOptions = {}) {
  return withFallback<ArrivalProfitability[]>(
    'arrival_profitability',
    async () => {
      const { data, error } = await supabase.rpc('arrival_profitability', {
        p_shop_id: shopId,
        p_include_test: opts.includeTest ?? false,
      })
      if (error) throw error
      return (data ?? []).map((r) => ({
        arrivalId: r.arrival_id,
        code: r.code,
        kind: r.kind,
        status: r.status,
        originCountry: r.origin_country,
        supplierName: r.supplier_name,
        orderDate: r.order_date,
        receivedDate: r.received_date,
        isTest: r.is_test,
        cost: Number(r.cost),
        revenue: Number(r.revenue),
        profit: Number(r.profit),
        recoveryPercent: Number(r.recovery_percent),
        remainingToRecover: Number(r.remaining_to_recover),
        soldUnits: Number(r.sold_units),
        remainingUnits: Number(r.remaining_units),
        productCount: Number(r.product_count),
      }))
    },
    async () =>
      (await arrivalProfitability(shopId))
        .filter((r) => opts.includeTest || !r.is_test)
        .map((r) => ({
          arrivalId: r.id,
          code: r.code,
          kind: r.kind,
          status: r.status,
          originCountry: r.origin,
          supplierName: r.supplier,
          orderDate: null,
          receivedDate: null,
          isTest: r.is_test,
          cost: r.cost,
          revenue: r.revenue,
          profit: r.profit,
          recoveryPercent: r.recovery,
          remainingToRecover: Math.max(r.cost - r.revenue, 0),
          soldUnits: r.sold,
          remainingUnits: r.remaining,
          productCount: r.productCount,
        })),
  )
}

/** Premier jour du mois local de `at` dans le fuseau `timeZone` ('YYYY-MM-01'), décalé de `shift` mois. */
export function monthStartIn(at: Date, timeZone = DEFAULT_TIME_ZONE, shift = 0) {
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone,
    year: 'numeric',
    month: 'numeric',
  }).formatToParts(at)
  const y = Number(parts.find((p) => p.type === 'year')?.value)
  const m = Number(parts.find((p) => p.type === 'month')?.value)
  const d = new Date(Date.UTC(y, m - 1 + shift, 1))
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}-01`
}

// Bénéfice estimé réel -----------------------------------------------------------------------

/**
 * Bénéfice estimé sur la période locale [from, to) ('YYYY-MM-DD', bornes absentes = sans limite).
 * null si la fonction n'existe pas encore en base : afficher alors « Reste après charges ».
 */
export function fetchEstimatedProfit(
  shopId: string,
  period: { from?: string; to?: string } = {},
  opts: InsightOptions = {},
) {
  return withFallback<EstimatedProfit | null>(
    'shop_estimated_profit',
    async () => {
      const { data, error } = await supabase.rpc('shop_estimated_profit', {
        p_shop_id: shopId,
        p_from: period.from,
        p_to: period.to,
        p_tz: opts.timeZone ?? DEFAULT_TIME_ZONE,
        p_include_test: opts.includeTest ?? false,
      })
      if (error) throw error
      return required<EstimatedProfit>(data, 'shop_estimated_profit')
    },
    async () => null,
  )
}
