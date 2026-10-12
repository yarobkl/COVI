// Charges, month by month: which month is shown, the months before and after it, and the totals
// (examples listed but never counted, like on Accueil).
import { localMonth } from '../../lib/dates'
import type { Expense } from '../../lib/types'

/** « 2026-10 » → first day of that month (local time). */
export const monthDate = (key: string) => {
  const [y, m] = key.split('-').map(Number)
  return new Date(y, m - 1, 1)
}

/** The month `delta` months after (or before, when negative) `key`. */
export const shiftMonth = (key: string, delta: number) => {
  const d = monthDate(key)
  return localMonth(new Date(d.getFullYear(), d.getMonth() + delta, 1))
}

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

/** « octobre », or « décembre 2025 » for another year than the current one. */
export function monthTitle(key: string, now: Date = new Date()) {
  const d = monthDate(key)
  const name = monthNames[d.getMonth()]
  return d.getFullYear() === now.getFullYear() ? name : `${name} ${d.getFullYear()}`
}

/** Month of an expense (its `expense_date` is a plain local date, 2026-10-02). */
export const expenseMonth = (e: Pick<Expense, 'expense_date'>) => e.expense_date.slice(0, 7)

/**
 * Months one can go to: from the first month with a charge (or the current one) to the current
 * month, or later if a charge was already noted for a coming month.
 */
export function monthRange(rows: Pick<Expense, 'expense_date'>[], now: Date = new Date()) {
  const current = localMonth(now)
  let first = current,
    last = current
  for (const r of rows) {
    const m = expenseMonth(r)
    if (m < first) first = m
    if (m > last) last = m
  }
  return { first, last }
}

/** What the month view offers: previous and next months, when there is one to go to. */
export function monthSteps(key: string, range: { first: string; last: string }) {
  const previous = shiftMonth(key, -1),
    next = shiftMonth(key, 1)
  return {
    previous: previous >= range.first ? previous : null,
    next: next <= range.last ? next : null,
  }
}

export type ExpenseTotals = {
  /** Charges counted (examples left out). */
  total: number
  /** Of which come back every month. */
  recurring: number
  /** Example lines present (listed, not counted). */
  examples: number
}

export function expenseTotals(rows: Expense[]): ExpenseTotals {
  let total = 0,
    recurring = 0,
    examples = 0
  for (const r of rows) {
    if (r.is_test) {
      examples += 1
      continue
    }
    total += Number(r.amount)
    if (r.recurring) recurring += Number(r.amount)
  }
  return { total, recurring, examples }
}

/** Charges of one month, most recent first. */
export const expensesOfMonth = (rows: Expense[], key: string) =>
  sortExpenses(rows.filter((r) => expenseMonth(r) === key))

/** Most recent first (the date, then the time it was noted). */
export const sortExpenses = (rows: Expense[]) =>
  [...rows].sort(
    (a, b) =>
      b.expense_date.localeCompare(a.expense_date) || b.created_at.localeCompare(a.created_at),
  )

/** Every charge grouped by month, the most recent month first (« Depuis le début »). */
export function byMonth(rows: Expense[]) {
  const months = new Map<string, Expense[]>()
  for (const r of sortExpenses(rows)) {
    const key = expenseMonth(r)
    months.set(key, [...(months.get(key) ?? []), r])
  }
  return [...months].map(([key, expenses]) => ({ key, expenses }))
}
