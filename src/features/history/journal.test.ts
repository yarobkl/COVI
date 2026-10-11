import { describe, expect, it } from 'vitest'
import type { Sale } from '../../lib/types'
import {
  dayLabel,
  filterLines,
  firstLines,
  fold,
  groupByDay,
  journalLines,
  methodsIn,
  periodStart,
} from './journal'

const now = new Date(2026, 9, 8, 15, 10) // jeudi 8 octobre

const item = (name: string, quantity: number, shown: number, sold: number, code = 'CHN-001') => ({
  quantity,
  initial_unit_price: shown,
  sold_unit_price: sold,
  products: {
    name,
    brand: null,
    arrival_id: 'a',
    image_path: null,
    image_url: null,
    arrivals: { code, kind: code.startsWith('BAL') ? 'balloon' : 'supplier_order' },
  },
})

let n = 0
const sale = (at: Date, method: string, items: Sale['sale_items'], is_test = false): Sale => ({
  id: `s-${++n}`,
  sold_at: at.toISOString(),
  payment_method: method,
  is_test,
  total_amount: items.reduce((t, i) => t + i.quantity * i.sold_unit_price, 0),
  sale_items: items,
})

const sales: Sale[] = [
  sale(new Date(2026, 9, 8, 14, 32), 'mobile_money', [item('Robe wax modèle A', 1, 18000, 18000)]),
  sale(new Date(2026, 9, 8, 11, 48), 'cash', [
    item('Chemise lin modèle C', 2, 12000, 12000),
    item('Veste en jean', 1, 15000, 13000, 'BAL-003'),
  ]),
  sale(new Date(2026, 9, 8, 9, 0), 'cash', [item('Pièce d’exemple', 1, 5000, 5000)], true),
  sale(new Date(2026, 9, 7, 18, 5), 'card', [item('Jean droit modèle B', 1, 22000, 20000)]),
  sale(new Date(2026, 9, 2, 10, 0), 'cash', [item('Robe pagne', 1, 10000, 10000, 'BAL-003')]),
  sale(new Date(2026, 8, 30, 17, 0), 'cash', [item('Élégante robe', 1, 9000, 9000)]),
]
const lines = journalLines(sales)

describe('journal lines', () => {
  it('flattens every article of every sale, most recent first', () => {
    expect(lines).toHaveLength(7)
    expect(lines[1]).toMatchObject({
      name: 'Chemise lin modèle C',
      quantity: 2,
      shownUnit: 12000,
      soldUnit: 12000,
      method: 'cash',
      arrivalCode: 'CHN-001',
      balloon: false,
      example: false,
    })
    expect(lines[2]).toMatchObject({ name: 'Veste en jean', balloon: true, soldUnit: 13000 })
    expect(lines[3].example).toBe(true)
  })

  it('names a deleted article', () => {
    const [line] = journalLines([
      { ...sales[0], sale_items: [{ ...sales[0].sale_items[0], products: null }] },
    ])
    expect(line.name).toBe('Article supprimé')
    expect(line.arrivalCode).toBeNull()
  })
})

describe('grouping by day', () => {
  it('says « Aujourd’hui », « Hier », then the spoken date', () => {
    expect(dayLabel(new Date(2026, 9, 8, 1, 0), now)).toBe('Aujourd’hui')
    expect(dayLabel(new Date(2026, 9, 7, 23, 59), now)).toBe('Hier')
    expect(dayLabel(new Date(2026, 9, 2), now)).toBe('Vendredi 2 octobre')
    expect(dayLabel(new Date(2025, 11, 24), now)).toBe('Mercredi 24 décembre 2025')
  })

  it('counts sales (not articles) and leaves examples out of the totals', () => {
    const days = groupByDay(lines, now)
    expect(days.map((d) => d.label)).toEqual([
      'Aujourd’hui',
      'Hier',
      'Vendredi 2 octobre',
      'Mercredi 30 septembre',
    ])
    expect(days[0]).toMatchObject({ count: 2, total: 18000 + 24000 + 13000 })
    expect(days[0].lines).toHaveLength(4) // the example is listed
    expect(days[1]).toMatchObject({ count: 1, total: 20000 })
  })

  it('groups by local day, not by UTC day', () => {
    // 23 h 30 local time is already the next day in UTC for a shop east of Greenwich.
    const late = journalLines([sale(new Date(2026, 9, 7, 23, 30), 'cash', [item('A', 1, 1, 1)])])
    expect(groupByDay(late, now)[0].label).toBe('Hier')
  })

  it('shows the first lines only, keeping each day’s full totals', () => {
    const days = groupByDay(lines, now)
    const shown = firstLines(days, 5)
    expect(shown.map((d) => d.lines.length)).toEqual([4, 1])
    expect(shown[1].total).toBe(20000)
    expect(firstLines(days, 2)).toHaveLength(1)
    expect(firstLines(days, 100)).toEqual(days)
  })
})

describe('filters', () => {
  const base = { method: null, query: '', now }

  it('starts each period in local time', () => {
    expect(periodStart('today', now)).toEqual(new Date(2026, 9, 8))
    expect(periodStart('week', now)).toEqual(new Date(2026, 9, 2))
    expect(periodStart('month', now)).toEqual(new Date(2026, 9, 1))
    expect(periodStart('all', now)).toBeNull()
    // The week crosses the start of the month.
    expect(periodStart('week', new Date(2026, 9, 3, 8))).toEqual(new Date(2026, 8, 27))
  })

  it('keeps the lines of the period', () => {
    const count = (period: 'today' | 'week' | 'month' | 'all') =>
      filterLines(lines, { ...base, period }).length
    expect(count('today')).toBe(4)
    expect(count('week')).toBe(6) // 2 → 8 octobre
    expect(count('month')).toBe(6)
    expect(count('all')).toBe(7)
  })

  it('filters by payment method', () => {
    const cards = filterLines(lines, { ...base, period: 'all', method: 'card' })
    expect(cards.map((l) => l.name)).toEqual(['Jean droit modèle B'])
  })

  it('searches the article, the arrival and the payment, accents and case ignored', () => {
    const find = (query: string) =>
      filterLines(lines, { ...base, period: 'all', query }).map((l) => l.name)
    expect(find('ROBE')).toEqual(['Robe wax modèle A', 'Robe pagne', 'Élégante robe'])
    expect(find('elegante')).toEqual(['Élégante robe'])
    expect(find('bal-003')).toEqual(['Veste en jean', 'Robe pagne'])
    expect(find('robe mobile')).toEqual(['Robe wax modèle A'])
    expect(find('  ')).toHaveLength(7)
    expect(fold(' Élégance ')).toBe('elegance')
  })

  it('lists the payment methods present, in the checkout order', () => {
    expect(methodsIn(lines)).toEqual(['cash', 'mobile_money', 'card'])
  })
})
