// The example shop's data shaped like the real pages expect it, so that the example looks and
// reads exactly like the application (journal, charges, bilan, arrivals).
import { paymentCode } from '../../lib/format'
import type { Expense } from '../../lib/types'
import type { JournalLine } from '../history/journal'
import type { ArrivalResult, BilanMonth } from '../statistics/bilanMath'
import { arrivals, monthlyExpenses, months, tickets } from './demoData'

/** In the example, « aujourd’hui » is the evening of 30 September 2026. */
export const demoNow = new Date(2026, 8, 30, 19, 30)

/** The sold lines, most recent sale first. */
export function demoJournal(): JournalLine[] {
  return [...tickets]
    .sort((a, b) => b.date.getTime() - a.date.getTime())
    .flatMap((t) =>
      t.lines.map((l, i) => ({
        key: `${t.id}-${i}`,
        saleId: t.id,
        soldAt: t.date,
        name: l.name,
        quantity: l.quantity,
        shownUnit: l.initial,
        soldUnit: l.sold,
        method: paymentCode(t.payment),
        arrivalCode: l.arrival,
        balloon: l.arrival.startsWith('BAL'),
        // The whole shop is an example: the banner says so once, the lines are not tagged.
        example: false,
      })),
    )
}

/** Sales (tickets with at least one article) and pieces sold over the three months. */
export function demoCounts() {
  const sold = tickets.filter((t) => t.lines.length > 0)
  return {
    sales: sold.length,
    pieces: sold.reduce((n, t) => n + t.lines.reduce((m, l) => m + l.quantity, 0), 0),
    total: sold.reduce((n, t) => n + t.total, 0),
  }
}

const monthKeys = ['2026-07', '2026-08', '2026-09']

/** The charges as rows of the « Charges » page: the rent, then the rest of the month. */
export function demoExpenses(): Expense[] {
  return monthlyExpenses.flatMap(([, rent, other], i) => {
    const key = monthKeys[i]
    const row = (id: string, day: string, category: string, label: string, amount: number) => ({
      id: `${key}-${id}`,
      shop_id: 'exemple',
      category,
      label,
      amount,
      expense_date: `${key}-${day}`,
      recurring: id === 'loyer',
      is_test: false,
      created_at: `${key}-${day}T09:00:00Z`,
    })
    return [
      row('autres', '20', 'Autre', 'électricité, sacs, frais Mobile Money', other),
      row('loyer', '02', 'Loyer', '', rent),
    ]
  })
}

/** Sales, charges and what is left, month by month (Bilan). */
export function demoBilan(): BilanMonth[] {
  return months.map((m, i) => ({
    key: monthKeys[i],
    label: m.name.toLowerCase(),
    sales: m.sales,
    count: m.buyers,
    charges: m.expenses,
    rest: m.sales - m.expenses,
  }))
}

/** What each arrival brought back, as the Bilan and Arrivages show it. */
export function demoArrivals(): ArrivalResult[] {
  return arrivals.map((a) => ({
    id: a.code,
    code: a.code,
    kind: a.kind,
    origin: `${a.origin} · ${a.received}`,
    cost: a.cost,
    revenue: a.revenue,
    recovery: Math.round((a.revenue / a.cost) * 100),
    sold: a.sold,
    remaining: a.remaining,
    example: false,
  }))
}

/** Pieces sold per category over the three months, most first. */
export function demoCategories() {
  const pieces = new Map<string, number>()
  for (const t of tickets)
    for (const l of t.lines) pieces.set(l.category, (pieces.get(l.category) ?? 0) + l.quantity)
  return [...pieces]
    .map(([category, count]) => ({ category, pieces: count }))
    .sort((a, b) => b.pieces - a.pieces)
}
