import { ProductThumb } from '../../components/ProductThumb'
import type { SoldItem } from '../../lib/covi'
import { money, paymentLabel } from '../../lib/format'

/** One sold line: product, date, payment, quantity, arrival and prices. */
export function SoldRow({ item: x }: { item: SoldItem }) {
  return (
    <div className="soldrow">
      <ProductThumb imageUrl={x.products?.image_url} fallback={x.products?.name?.[0] ?? 'V'} />
      <div className="grow">
        <b>
          {x.products?.name ?? 'Produit'} {x.is_test && <em className="test-tag">TEST</em>}
        </b>
        <span>
          {new Date(x.sold_at).toLocaleString('fr-FR')} · {paymentLabel(x.payment_method)} · Qté{' '}
          {x.quantity}
          {x.products?.arrivals?.code ? ' · ' + x.products.arrivals.code : ''}
        </span>
      </div>
      <span>
        Prix initial<b>{money(Number(x.initial_unit_price))}</b>
      </span>
      <span>
        Prix vendu<b>{money(Number(x.sold_unit_price))}</b>
      </span>
    </div>
  )
}
