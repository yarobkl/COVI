import { Ledger, LedgerRow, Sheet } from '../../components/ui'
import { money } from '../../lib/format'
import { monthlyExpenses } from './demoData'

export function DemoExpenses() {
  return (
    <Sheet aria-labelledby="demo-expenses-title">
      <h2 className="section-title" id="demo-expenses-title">
        Charges par mois
      </h2>
      <p className="muted">Charges ponctuelles et récurrentes de la simulation.</p>
      {monthlyExpenses.map(([month, rent, other, total]) => (
        <Ledger key={month} label={`Charges de ${month}`}>
          <LedgerRow variant="head" label={month} />
          <LedgerRow
            variant="sub"
            label="Loyer"
            value={<span className="figures amount-out">− {money(rent)}</span>}
          />
          <LedgerRow
            variant="sub"
            label="Autres charges"
            value={<span className="figures amount-out">− {money(other)}</span>}
          />
          <LedgerRow
            variant="total"
            label={`Total ${month}`}
            value={<span className="figures">{money(total)}</span>}
          />
        </Ledger>
      ))}
    </Sheet>
  )
}
