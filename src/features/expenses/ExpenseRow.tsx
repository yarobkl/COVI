import { money } from '../../lib/format'
import type { Expense } from '../../lib/operations'

export function ExpenseRow({
  expense: x,
  onEdit,
  onDelete,
}: {
  expense: Expense
  onEdit: () => void
  onDelete: () => void
}) {
  return (
    <div className="expense">
      <div className="grow">
        <b>
          {x.label || x.category} {x.is_test && <em className="test-tag">TEST</em>}
        </b>
        <span>
          {x.category} · {x.expense_date}
          {x.recurring ? ' · Récurrente' : ''}
        </span>
      </div>
      <b>- {money(Number(x.amount))}</b>
      <button className="outline" onClick={onEdit}>
        Modifier
      </button>
      <button className="outline" onClick={onDelete}>
        Supprimer
      </button>
    </div>
  )
}
