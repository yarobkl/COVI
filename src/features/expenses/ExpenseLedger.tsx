import { TrashIcon } from '../../components/icons'
import { Amount, Badge, IconButton } from '../../components/ui'
import { shortDay } from '../../lib/dates'
import { fcfa, money } from '../../lib/format'
import type { Expense } from '../../lib/types'
import '../../styles/app/charges.css'
import { categoryLabel } from './expenseCategories'
import { expenseTotals, monthTitle } from './expenseMonths'

export type ExpenseView = 'month' | 'all'

/** The figure of the screen: « Octobre : 140 000 FCFA de charges », and what comes back monthly. */
export function ExpensesHero({
  view,
  month,
  now,
  rows,
}: {
  view: ExpenseView
  month: string
  now: Date
  rows: Expense[]
}) {
  const { total, recurring, examples } = expenseTotals(rows)
  const title = monthTitle(month, now)
  return (
    <section className="charges-hero" aria-label="Total des charges">
      <p className="charges-hero__lead">
        {view === 'month'
          ? `${title.charAt(0).toUpperCase()}${title.slice(1)} :`
          : 'Depuis le début :'}
      </p>
      <p className="amount amount--hero charges-hero__amount">
        {fcfa(total)}
        <span className="amount__unit">FCFA</span>
      </p>
      <p className="charges-hero__sub">
        de charges
        {recurring > 0 && (
          <>
            , dont <strong className="figures">{fcfa(recurring)}</strong>&nbsp;FCFA qui reviennent
            chaque mois
          </>
        )}
        .
      </p>
      {examples > 0 && (
        <p className="charges-hero__note">
          Les lignes « Exemple » viennent de la boutique d’exemple : elles ne sont pas comptées.
        </p>
      )}
    </section>
  )
}

/**
 * The charges of a month in red notebook lines (« Loyer · 2 oct. · chaque mois ····· − 90 000 »)
 * and their total. Touching a line opens it to change it; the bin asks to delete it. Without
 * `onEdit` the lines are read-only (example shop).
 */
export function ExpenseLedger({
  title,
  totalLabel,
  expenses,
  onEdit,
  onDelete,
}: {
  /** Month heading, when several months follow each other. */
  title?: string
  totalLabel: string
  expenses: Expense[]
  onEdit?: (expense: Expense) => void
  onDelete?: (expense: Expense) => void
}) {
  const { total } = expenseTotals(expenses)
  const list = (
    <ul className="ledger charges-ledger">
      {expenses.map((e) => {
        const name = categoryLabel(e.category)
        const meta = (
          <span className="ledger__meta">
            {shortDay(new Date(`${e.expense_date}T12:00:00`))}
            {e.label && ` · ${e.label}`}
            {e.recurring && (
              <>
                {' '}
                <Badge>chaque mois</Badge>
              </>
            )}
            {e.is_test && (
              <>
                {' '}
                <Badge>Exemple</Badge>
              </>
            )}
          </span>
        )
        return (
          <li
            key={e.id}
            className={`ledger__row charge-row${onEdit ? ' ledger__row--link' : ''}${e.is_test ? ' charge-row--example' : ''}`}
          >
            <span className="ledger__label">
              {onEdit ? (
                <button
                  type="button"
                  className="charge-row__open"
                  aria-label={`Modifier ${name}, ${money(Number(e.amount))}`}
                  onClick={() => onEdit(e)}
                >
                  {name}
                </button>
              ) : (
                name
              )}
              {meta}
            </span>
            <span className="ledger__dots" aria-hidden="true" />
            <span className="ledger__value">
              <Amount value={-Number(e.amount)} tone="out" regular />
            </span>
            {onDelete && (
              <IconButton
                className="charge-row__delete"
                variant="danger"
                label={`Supprimer ${name}`}
                onClick={() => onDelete(e)}
              >
                <TrashIcon />
              </IconButton>
            )}
          </li>
        )
      })}
      <li className="ledger__row ledger__row--total">
        <span className="ledger__label">{totalLabel}</span>
        <span className="ledger__dots" aria-hidden="true" />
        <span className="ledger__value">
          <Amount value={-total} tone={total > 0 ? 'out' : undefined} />
        </span>
        {onDelete && <span className="charge-row__spacer" aria-hidden="true" />}
      </li>
    </ul>
  )
  if (!title) return list
  const heading = title.charAt(0).toUpperCase() + title.slice(1)
  return (
    <section className="charges-month" aria-label={heading}>
      <h2 className="section-title">{heading}</h2>
      {list}
    </section>
  )
}
