// The « Noter une charge » sheet: what was typed, checked before it is sent.
import { parseAmount } from '../../lib/format'
import type { ExpenseInput } from '../../lib/operations'
import type { Expense } from '../../lib/types'
import { categoryLabel, expenseCategories } from './expenseCategories'

export type ExpenseDraft = {
  category: string
  label: string
  /** As typed (« 90 000 »). */
  amount: string
  /** yyyy-mm-dd, as given by the date field. */
  date: string
  recurring: boolean
}

/** A new charge (paid today), or the charge being changed, as the sheet starts. */
export function draftOf(expense: Expense | null, today: string): ExpenseDraft {
  if (!expense)
    return { category: expenseCategories[0], label: '', amount: '', date: today, recurring: false }
  return {
    category: categoryLabel(expense.category),
    label: expense.label,
    amount: String(expense.amount),
    date: expense.expense_date,
    recurring: expense.recurring,
  }
}

/** What to send, or the message to show under the field that needs fixing. */
export function readDraft(
  draft: ExpenseDraft,
): { input: ExpenseInput } | { field: 'amount' | 'date'; error: string } {
  const amount = parseAmount(draft.amount)
  if (!amount || amount <= 0) return { field: 'amount', error: 'Indiquez un montant en FCFA.' }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(draft.date))
    return { field: 'date', error: 'Indiquez le jour où vous avez payé.' }
  return {
    input: {
      category: draft.category,
      label: draft.label.trim(),
      amount,
      expense_date: draft.date,
      recurring: draft.recurring,
    },
  }
}
