import { Ledger, LedgerRow } from '../../components/ui'
import { money, plural } from '../../lib/format'
import type { Expense } from '../../lib/types'

/** Totals of the expenses visible for the selected period, as the foot of a notebook page. */
export function ExpenseSummary({
  visible,
  period,
}: {
  visible: Expense[]
  period: 'month' | 'all'
}) {
  const total = visible.reduce((n, x) => n + Number(x.amount), 0)
  const recurring = visible.filter((x) => x.recurring).reduce((n, x) => n + Number(x.amount), 0)
  return (
    <Ledger label="Totaux des charges">
      <LedgerRow
        label="Charges récurrentes"
        value={<span className="figures">{money(recurring)}</span>}
      />
      <LedgerRow
        variant="total"
        label={period === 'month' ? 'Total du mois' : 'Total'}
        meta={plural(visible.length, 'écriture')}
        value={<span className="figures">{money(total)}</span>}
      />
    </Ledger>
  )
}
