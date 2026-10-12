import { describe, expect, it } from 'vitest'
import { groupByDay } from '../history/journal'
import { arrivals, months, remainingStock } from './demoData'
import {
  demoArrivals,
  demoBilan,
  demoCategories,
  demoCounts,
  demoExpenses,
  demoJournal,
  demoNow,
} from './demoViews'

// The example shop must never contradict itself: every page shows the same figures.
describe('example shop', () => {
  it('sells, month by month, what the bilan says', () => {
    const journal = demoJournal()
    const perMonth = new Map<number, number>()
    for (const l of journal)
      perMonth.set(
        l.soldAt.getMonth(),
        (perMonth.get(l.soldAt.getMonth()) ?? 0) + l.soldUnit * l.quantity,
      )
    expect([...perMonth.entries()].sort()).toEqual([
      [6, months[0].sales],
      [7, months[1].sales],
      [8, months[2].sales],
    ])
    expect(demoCounts().total).toBe(months.reduce((n, m) => n + m.sales, 0))
    expect(demoCounts().pieces).toBe(months.reduce((n, m) => n + m.units, 0))
    expect(demoCounts().sales).toBe(months.reduce((n, m) => n + m.buyers, 0))
  })

  it('matches the arrivals and what is left in stock', () => {
    const sold = new Map<string, number>()
    const revenue = new Map<string, number>()
    for (const l of demoJournal()) {
      sold.set(l.arrivalCode!, (sold.get(l.arrivalCode!) ?? 0) + l.quantity)
      revenue.set(l.arrivalCode!, (revenue.get(l.arrivalCode!) ?? 0) + l.soldUnit * l.quantity)
    }
    for (const a of arrivals) {
      expect(sold.get(a.code)).toBe(a.sold)
      expect(revenue.get(a.code)).toBe(a.revenue)
      const left = remainingStock.filter((r) => r[1] === a.code).reduce((n, r) => n + r[2], 0)
      expect(left).toBe(a.remaining)
    }
    expect(demoArrivals().find((a) => a.code === 'BAL-001')).toMatchObject({ recovery: 252 })
  })

  it('notes the charges of each month', () => {
    const charges = demoExpenses()
    for (const [i, m] of months.entries()) {
      const key = `2026-0${7 + i}`
      const total = charges
        .filter((c) => c.expense_date.startsWith(key))
        .reduce((n, c) => n + c.amount, 0)
      expect(total).toBe(m.expenses)
    }
    expect(demoBilan().map((m) => m.rest)).toEqual([384000, 856000, 714000])
  })

  it('reads like the real journal, with names from the shop', () => {
    const days = groupByDay(demoJournal(), demoNow)
    expect(days[0].label).toBe('Hier') // dernière vente le 29 septembre
    const names = new Set(demoJournal().map((l) => l.name))
    expect(names.has('Robe wax modèle A')).toBe(true)
    expect(
      [...names].some((n) => /modèle D$|Pièce ballon|Article/.test(n) && !n.includes('brodé')),
    ).toBe(false)
    expect(demoCategories()[0]).toEqual({ category: 'Friperie', pieces: 46 })
  })
})
