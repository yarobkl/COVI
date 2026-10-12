import { ProductThumb } from '../../components/ProductThumb'
import { money, paymentLabel } from '../../lib/format'
import type { CategorySaleHistory } from '../../lib/categorySaleHistory'

/** A category sale never fabricates a product SKU or individual purchase cost. */
export function CategorySoldRow({
  receipt,
  line,
}: {
  receipt: CategorySaleHistory
  line: CategorySaleHistory['lines'][number]
}) {
  return (
    <div className="soldrow">
      <ProductThumb fallback={line.label[0] ?? 'V'} />
      <div className="grow">
        <b>
          {line.label} {receipt.isTest && <em className="test-tag">TEST</em>}
        </b>
        <span>
          {new Date(receipt.confirmedAt).toLocaleString('fr-FR')} ·{' '}
          {paymentLabel(receipt.method)} · Qté {line.quantity} · Reçu {receipt.receiptNumber}
          {' · '}Encaissé par : {receipt.cashierFirstName}
        </span>
      </div>
      <span>
        Prix négocié / pièce<b>{money(line.lineTotalXaf / line.quantity)}</b>
      </span>
      <span>
        Total de la ligne<b>{money(line.lineTotalXaf)}</b>
      </span>
    </div>
  )
}
