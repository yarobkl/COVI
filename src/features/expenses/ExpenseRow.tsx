import { Button } from '../../components/ui'
import { isoDayLabel } from '../../lib/dates'
import { money } from '../../lib/format'
import type { Expense } from '../../lib/types'

/** One expense written as a line of the notebook, with its two small actions under it. */
export function ExpenseRow({
  expense: x,
  onEdit,
  onDelete,
}: {
  expense: Expense
  onEdit: () => void
  onDelete: () => void
}) {
  const name = x.label || x.category
  return (
    <li className="ledger__row expense-row">
      <span className="ledger__label">
        {name}
        {x.is_test && <span className="test-note">test</span>}
        <span className="ledger__meta">
          {[x.category, isoDayLabel(x.expense_date), x.recurring ? 'récurrente' : null]
            .filter(Boolean)
            .join(' · ')}
        </span>
      </span>
      <span className="ledger__dots" aria-hidden="true" />
      <span className="ledger__value figures amount-out">− {money(Number(x.amount))}</span>
      <span className="row-actions expense-row__actions">
        <Button variant="secondary" onClick={onEdit} aria-label={`Modifier ${name}`}>
          Modifier
        </Button>
        <Button variant="ghost" onClick={onDelete} aria-label={`Supprimer ${name}`}>
          Supprimer
        </Button>
      </span>
    </li>
  )
}
