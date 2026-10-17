import { Ledger, LedgerRow, Sheet } from '../../components/ui'
import { money, plural } from '../../lib/format'
import { remainingStock } from './demoData'

export function DemoStock() {
  return (
    <Sheet aria-labelledby="demo-stock-title">
      <h2 className="section-title" id="demo-stock-title">
        Stock au 30 septembre
      </h2>
      <p className="muted">12 produits encore disponibles dans cette simulation.</p>
      <Ledger label="Stock restant">
        {remainingStock.map(([name, arrival, quantity, price]) => (
          <LedgerRow
            key={arrival + '-' + name}
            label={name}
            meta={`${arrival} · ${plural(quantity, 'restant')}`}
            value={<span className="figures">{money(Number(price))}</span>}
          />
        ))}
      </Ledger>
    </Sheet>
  )
}
