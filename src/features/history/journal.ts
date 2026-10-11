// The sales journal: every sold line, grouped by day like the pages of the shop's notebook
// (« Aujourd’hui · 7 ventes · 126 000 »), with the period, payment and search filters.
import { localDay, longDay } from '../../lib/dates'
import { paymentLabel } from '../../lib/format'
import type { Sale } from '../../lib/types'

/** One line of the journal: one article of one sale. */
export type JournalLine = {
  /** Unique key of the line (sale id + position). */
  key: string
  saleId: string
  soldAt: Date
  name: string
  quantity: number
  /** Displayed price of one piece. */
  shownUnit: number
  /** Price actually paid for one piece. */
  soldUnit: number
  /** Payment code stored in `sales` (cash, mobile_money…). */
  method: string
  arrivalCode: string | null
  balloon: boolean
  /** Example data (« boutique d’exemple »): listed, never counted. */
  example: boolean
}

export type Period = 'today' | 'week' | 'month' | 'all'

export const periods: readonly { value: Period; label: string }[] = [
  { value: 'today', label: 'Aujourd’hui' },
  { value: 'week', label: '7 jours' },
  { value: 'month', label: 'Ce mois' },
  { value: 'all', label: 'Tout' },
]

/** listSales() returns at most this many sales (the most recent ones). */
export const SALES_LIMIT = 500

/** Lines of the sales, most recent sale first (the order of listSales). */
export function journalLines(sales: Sale[]): JournalLine[] {
  return sales.flatMap((s) =>
    (s.sale_items ?? []).map((item, i) => ({
      key: `${s.id}-${i}`,
      saleId: s.id,
      soldAt: new Date(s.sold_at),
      name: item.products?.name ?? 'Article supprimé',
      quantity: Number(item.quantity),
      shownUnit: Number(item.initial_unit_price),
      soldUnit: Number(item.sold_unit_price),
      method: s.payment_method,
      arrivalCode: item.products?.arrivals?.code ?? null,
      balloon: item.products?.arrivals?.kind === 'balloon',
      example: s.is_test,
    })),
  )
}

/** First instant of the period in local time (`null` for « Tout »). */
export function periodStart(period: Period, now: Date): Date | null {
  switch (period) {
    case 'today':
      return new Date(now.getFullYear(), now.getMonth(), now.getDate())
    case 'week':
      // Today and the 6 days before it.
      return new Date(now.getFullYear(), now.getMonth(), now.getDate() - 6)
    case 'month':
      return new Date(now.getFullYear(), now.getMonth(), 1)
    case 'all':
      return null
  }
}

/** Lower case, without accents: « Élégance » and « elegance » match. */
export const fold = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim()

export type JournalFilter = {
  period: Period
  /** Payment code, or `null` for every method. */
  method: string | null
  query: string
  now: Date
}

/** Lines kept by the filters: period, payment method, and words of the article or arrival. */
export function filterLines(lines: JournalLine[], { period, method, query, now }: JournalFilter) {
  const start = periodStart(period, now)
  const words = fold(query).split(/\s+/).filter(Boolean)
  return lines.filter((l) => {
    if (start && l.soldAt < start) return false
    if (method && l.method !== method) return false
    if (!words.length) return true
    const text = fold(`${l.name} ${l.arrivalCode ?? ''} ${paymentLabel(l.method)}`)
    return words.every((w) => text.includes(w))
  })
}

export type JournalDay = {
  /** Local day key (2026-10-08). */
  key: string
  /** « Aujourd’hui », « Hier », « Mardi 6 octobre ». */
  label: string
  /** Real sales of the day (examples not counted). */
  count: number
  /** Amount received that day (examples not counted). */
  total: number
  lines: JournalLine[]
}

/** « Aujourd’hui », « Hier », otherwise the spoken date (with the year when it is not this one). */
export function dayLabel(d: Date, now: Date): string {
  if (localDay(d) === localDay(now)) return 'Aujourd’hui'
  const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
  if (localDay(d) === localDay(yesterday)) return 'Hier'
  const day = longDay(d)
  return d.getFullYear() === now.getFullYear() ? day : `${day} ${d.getFullYear()}`
}

/**
 * Lines grouped by local day, in the order they come (most recent first). Each day counts its
 * sales (a sale of two articles counts once) and adds up what was paid; examples are listed but
 * left out of both.
 */
export function groupByDay(lines: JournalLine[], now: Date): JournalDay[] {
  const days: JournalDay[] = []
  const sales = new Map<string, Set<string>>()
  for (const line of lines) {
    const key = localDay(line.soldAt)
    let day = days.find((d) => d.key === key)
    if (!day) {
      day = { key, label: dayLabel(line.soldAt, now), count: 0, total: 0, lines: [] }
      days.push(day)
      sales.set(key, new Set())
    }
    day.lines.push(line)
    if (line.example) continue
    day.total += line.soldUnit * line.quantity
    const seen = sales.get(key)!
    if (!seen.has(line.saleId)) {
      seen.add(line.saleId)
      day.count += 1
    }
  }
  return days
}

/**
 * The first `limit` lines, still grouped by day (« Voir plus » shows the next ones). Day headings
 * keep the totals of the whole day, even when only part of it is shown yet.
 */
export function firstLines(days: JournalDay[], limit: number): JournalDay[] {
  const shown: JournalDay[] = []
  let left = limit
  for (const day of days) {
    if (left <= 0) break
    shown.push(left >= day.lines.length ? day : { ...day, lines: day.lines.slice(0, left) })
    left -= day.lines.length
  }
  return shown
}

/** Payment methods present in the lines, in the checkout order. */
export function methodsIn(lines: JournalLine[]): string[] {
  const order = ['cash', 'mobile_money', 'card', 'bank_transfer', 'other']
  const present = new Set(lines.map((l) => l.method))
  return [...present].sort((a, b) => {
    const ia = order.indexOf(a),
      ib = order.indexOf(b)
    return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
  })
}
