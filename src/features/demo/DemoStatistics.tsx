import { Ledger, LedgerRow, Sheet } from '../../components/ui'
import { money } from '../../lib/format'

export function DemoStatistics() {
  return (
    <div className="page-pair">
      <Sheet aria-labelledby="demo-stats-title">
        <h2 className="section-title" id="demo-stats-title">
          Les trois mois
        </h2>
        <Ledger label="Chiffres des trois mois">
          <LedgerRow label="Tickets clients" value="105" />
          <LedgerRow label="Articles vendus" value="143" />
          <LedgerRow label="Stock restant" value="12 articles" />
          <LedgerRow
            variant="total"
            label="Ventes encaissées"
            value={<span className="figures">{money(2334000)}</span>}
          />
        </Ledger>
      </Sheet>
      <Sheet aria-labelledby="demo-top-title">
        <h2 className="section-title" id="demo-top-title">
          Les plus vendus
        </h2>
        <Ledger label="Articles les plus vendus">
          <LedgerRow label="1. Article modèle D" value="35 vendus" />
          <LedgerRow label="2. Chemise modèle C" value="28 vendues" />
          <LedgerRow label="3. Robe modèle A" value="20 vendues" />
        </Ledger>
      </Sheet>
    </div>
  )
}
