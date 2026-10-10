import { describe, expect, it } from 'vitest'
import type { Expense } from '../../lib/types'
import { categoryLabel, expenseCategories } from './expenseCategories'
import { draftOf, readDraft } from './expenseForm'
import {
  byMonth,
  expensesOfMonth,
  expenseTotals,
  monthRange,
  monthSteps,
  monthTitle,
  shiftMonth,
} from './expenseMonths'

const now = new Date(2026, 9, 8, 15, 0)
const expense = (
  id: string,
  date: string,
  amount: number,
  extra: Partial<Expense> = {},
): Expense => ({
  id,
  shop_id: 'shop-1',
  category: 'Loyer',
  label: '',
  amount,
  expense_date: date,
  recurring: false,
  is_test: false,
  created_at: `${date}T10:00:00Z`,
  ...extra,
})

const rows = [
  expense('e1', '2026-10-02', 90000, { recurring: true }),
  expense('e2', '2026-10-05', 25000, { category: 'Électricité', recurring: true }),
  expense('e3', '2026-10-03', 20000, { category: 'Sacs' }),
  expense('e4', '2026-10-06', 7000, { is_test: true }),
  expense('e5', '2026-09-02', 90000, { recurring: true }),
  expense('e6', '2026-07-01', 70000),
]

describe('month navigation', () => {
  it('moves between months, across years', () => {
    expect(shiftMonth('2026-10', -1)).toBe('2026-09')
    expect(shiftMonth('2026-01', -1)).toBe('2025-12')
    expect(shiftMonth('2026-12', 1)).toBe('2027-01')
    expect(shiftMonth('2026-10', -12)).toBe('2025-10')
  })

  it('names the month, with the year when it is not this one', () => {
    expect(monthTitle('2026-09', now)).toBe('septembre')
    expect(monthTitle('2025-12', now)).toBe('décembre 2025')
  })

  it('goes from the first charge to the current month', () => {
    const range = monthRange(rows, now)
    expect(range).toEqual({ first: '2026-07', last: '2026-10' })
    expect(monthSteps('2026-10', range)).toEqual({ previous: '2026-09', next: null })
    expect(monthSteps('2026-08', range)).toEqual({ previous: '2026-07', next: '2026-09' })
    expect(monthSteps('2026-07', range)).toEqual({ previous: null, next: '2026-08' })
  })

  it('reaches a coming month when a charge is already noted for it', () => {
    const range = monthRange([...rows, expense('f', '2026-11-01', 90000)], now)
    expect(range.last).toBe('2026-11')
    expect(monthRange([], now)).toEqual({ first: '2026-10', last: '2026-10' })
  })
})

describe('totals', () => {
  it('adds the month’s charges and what comes back, examples left out', () => {
    const october = expensesOfMonth(rows, '2026-10')
    expect(october.map((e) => e.id)).toEqual(['e4', 'e2', 'e3', 'e1']) // most recent first
    expect(expenseTotals(october)).toEqual({ total: 135000, recurring: 115000, examples: 1 })
    expect(expenseTotals([])).toEqual({ total: 0, recurring: 0, examples: 0 })
  })

  it('groups every charge by month, the most recent month first', () => {
    expect(byMonth(rows).map((m) => [m.key, m.expenses.length])).toEqual([
      ['2026-10', 4],
      ['2026-09', 1],
      ['2026-07', 1],
    ])
  })
})

describe('categories', () => {
  it('reads old stored names with their new wording', () => {
    expect(categoryLabel('Sacs')).toBe('Sacs et emballages')
    expect(categoryLabel('Emballage')).toBe('Sacs et emballages')
    expect(categoryLabel('Téléphone')).toBe('Crédit téléphone')
    expect(categoryLabel('Loyer')).toBe('Loyer')
    expect(expenseCategories).toContain('Ticket de marché / droit de place')
    expect(expenseCategories).not.toContain('Tontine')
  })
})

describe('expense sheet', () => {
  it('starts a new charge paid today, or the charge being changed', () => {
    expect(draftOf(null, '2026-10-08')).toEqual({
      category: 'Loyer',
      label: '',
      amount: '',
      date: '2026-10-08',
      recurring: false,
    })
    expect(draftOf(rows[2], '2026-10-08')).toMatchObject({
      category: 'Sacs et emballages',
      amount: '20000',
      date: '2026-10-03',
    })
  })

  it('asks for an amount and a date, and sends whole francs', () => {
    const draft = draftOf(null, '2026-10-08')
    expect(readDraft(draft)).toEqual({ field: 'amount', error: 'Indiquez un montant en FCFA.' })
    expect(readDraft({ ...draft, amount: '0' })).toMatchObject({ field: 'amount' })
    expect(readDraft({ ...draft, amount: '5 000', date: '' })).toMatchObject({ field: 'date' })
    expect(readDraft({ ...draft, amount: '90 000', label: '  loyer d’octobre ' })).toEqual({
      input: {
        category: 'Loyer',
        label: 'loyer d’octobre',
        amount: 90000,
        expense_date: '2026-10-08',
        recurring: false,
      },
    })
  })
})
