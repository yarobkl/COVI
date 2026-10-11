// Bilan: the last three complete months (sales, charges, what is left), what sells best and
// what each arrival brought back. Only figures read from the account; examples are left out
// unless the seller asks to include them.
import { localMonth } from '../../lib/dates'
import type { ArrivalProfitability } from '../../lib/insights'
import type { Statistics } from '../../lib/operations'

const monthNames = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
]

export type BilanMonth = {
  key: string
  /** « juillet » */
  label: string
  /** Money received from sales. */
  sales: number
  count: number
  charges: number
  /** Sales minus charges (what the goods cost is not taken off). */
  rest: number
}

/** The three complete months before the current one, oldest first. */
export function lastMonths(now: Date, n = 3): { key: string; label: string }[] {
  return Array.from({ length: n }, (_, i) => {
    const d = new Date(now.getFullYear(), now.getMonth() - n + i, 1)
    return { key: localMonth(d), label: monthNames[d.getMonth()] }
  })
}

const keep = (includeExamples: boolean) => (row: { is_test: boolean }) =>
  includeExamples || !row.is_test

/** Sales, charges and what is left, month by month. */
export function monthlyBilan(
  stats: Pick<Statistics, 'sales' | 'expenses'>,
  months: { key: string; label: string }[],
  includeExamples: boolean,
): BilanMonth[] {
  const rows = months.map((m) => ({ ...m, sales: 0, count: 0, charges: 0, rest: 0 }))
  const byKey = new Map(rows.map((r) => [r.key, r]))
  for (const s of stats.sales.filter(keep(includeExamples))) {
    const month = byKey.get(localMonth(new Date(s.sold_at)))
    if (!month) continue
    month.sales += Number(s.total_amount)
    month.count += 1
  }
  for (const e of stats.expenses.filter(keep(includeExamples))) {
    const month = byKey.get(e.expense_date.slice(0, 7))
    if (month) month.charges += Number(e.amount)
  }
  for (const r of rows) r.rest = r.sales - r.charges
  return rows
}

/** Sum of the months: the hero figure and the total line. */
export const bilanTotal = (months: BilanMonth[]) =>
  months.reduce(
    (t, m) => ({
      sales: t.sales + m.sales,
      count: t.count + m.count,
      charges: t.charges + m.charges,
      rest: t.rest + m.rest,
    }),
    { sales: 0, count: 0, charges: 0, rest: 0 },
  )

/** What sells best over the months: pieces sold per category, most first. */
export function topCategories(
  sales: Statistics['sales'],
  months: { key: string }[],
  includeExamples: boolean,
  n = 5,
): { category: string; pieces: number }[] {
  const keys = new Set(months.map((m) => m.key))
  const pieces = new Map<string, number>()
  for (const s of sales.filter(keep(includeExamples))) {
    if (!keys.has(localMonth(new Date(s.sold_at)))) continue
    for (const i of s.sale_items ?? []) {
      const category = i.products?.category?.trim() || 'Autre'
      pieces.set(category, (pieces.get(category) ?? 0) + Number(i.quantity))
    }
  }
  return [...pieces]
    .map(([category, count]) => ({ category, pieces: count }))
    .sort((a, b) => b.pieces - a.pieces || a.category.localeCompare(b.category, 'fr'))
    .slice(0, n)
}

/** An arrival as the Bilan shows it (also built from the example shop's data). */
export type ArrivalResult = {
  id: string
  code: string
  kind: 'supplier_order' | 'balloon'
  origin: string | null
  /** What it cost (goods, transport, customs; or the bale's global price). */
  cost: number
  /** Money its pieces brought in. */
  revenue: number
  /** Revenue / cost, in % (0 when the cost is unknown). */
  recovery: number
  sold: number
  remaining: number
  example: boolean
}

/**
 * Arrivals to compare: those received (or already selling). Those still ordered or on their way
 * are only counted, to say they are not there yet.
 */
export function arrivalResults(profit: ArrivalProfitability[], includeExamples: boolean) {
  const kept = profit.filter((a) => includeExamples || !a.isTest)
  const shown = kept.filter((a) => a.status === 'received' || a.revenue > 0)
  return {
    shown: shown.map((a): ArrivalResult => ({
      id: a.arrivalId,
      code: a.code,
      kind: a.kind === 'balloon' ? 'balloon' : 'supplier_order',
      origin: a.originCountry,
      cost: a.cost,
      revenue: a.revenue,
      recovery: a.recoveryPercent,
      sold: a.soldUnits,
      remaining: a.remainingUnits,
      example: a.isTest,
    })),
    notReceived: kept.length - shown.length,
  }
}

/** Example data present in the Bilan (sales, charges or arrivals): the switch is offered. */
export const hasExamples = (
  stats: Pick<Statistics, 'sales' | 'expenses'>,
  arrivals: Pick<ArrivalProfitability, 'isTest'>[],
) =>
  stats.sales.some((s) => s.is_test) ||
  stats.expenses.some((e) => e.is_test) ||
  arrivals.some((a) => a.isTest)

/** Local bounds [from, to) of a 'YYYY-MM' month, as shop_estimated_profit takes them. */
export function monthRange(key: string) {
  const [y, m] = key.split('-').map(Number)
  const next = new Date(Date.UTC(y, m, 1))
  return {
    from: `${key}-01`,
    to: `${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(2, '0')}-01`,
  }
}
