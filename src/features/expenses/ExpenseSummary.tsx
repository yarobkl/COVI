import { money } from '../../lib/format'
import type { Expense } from '../../lib/types'

/** Totals of the expenses visible for the selected period. */
export function ExpenseSummary({
  visible,
  period,
}: {
  visible: Expense[]
  period: 'month' | 'all'
}) {
  const total = visible.reduce((n, x) => n + Number(x.amount), 0)
  return (
    <div className="summary3">
      <div className="kpi">
        <span>Charges sur la période</span>
        <b>{money(total)}</b>
        <small>
          {period === 'month' ? 'Ce mois-ci' : 'Tout l’historique, y compris les lignes TEST'}
        </small>
      </div>
      <div className="kpi">
        <span>Charges récurrentes</span>
        <b>{money(visible.filter((x) => x.recurring).reduce((n, x) => n + Number(x.amount), 0))}</b>
        <small>Identifiées sur la période</small>
      </div>
      <div className="kpi">
        <span>Écritures</span>
        <b>{visible.length}</b>
        <small>Charges enregistrées</small>
      </div>
    </div>
  )
}
