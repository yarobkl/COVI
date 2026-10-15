import { LedgerRow } from '../../components/ui'
import { whenLabel } from '../../lib/dates'
import { money, paymentLabel } from '../../lib/format'
import type { SoldItem } from '../../lib/types'

/**
 * Une vente écrite comme une ligne du cahier : article · pointillés · prix vendu ; dessous la
 * date, le règlement, la quantité et l'arrivage. Le prix initial barré seulement s'il a changé.
 */
export function SoldRow({ item: x }: { item: SoldItem }) {
  const initial = Number(x.initial_unit_price)
  const sold = Number(x.sold_unit_price)
  return (
    <LedgerRow
      className="sold-row"
      label={
        <>
          <span className="sold-row__name">
            {x.quantity > 1 && <span className="figures">{x.quantity} × </span>}
            {x.products?.name ?? 'Produit'}
          </span>
          {x.is_test && <span className="sold-row__test">test</span>}
        </>
      }
      meta={[
        whenLabel(new Date(x.sold_at)),
        paymentLabel(x.payment_method),
        x.products?.arrivals?.code,
      ]
        .filter(Boolean)
        .join(' · ')}
      value={
        <span className="sold-row__price">
          {initial !== sold && (
            <s className="figures sold-row__initial" aria-label={`Prix initial ${money(initial)}`}>
              {money(initial)}
            </s>
          )}
          <span className="figures">{money(sold)}</span>
        </span>
      }
    />
  )
}
