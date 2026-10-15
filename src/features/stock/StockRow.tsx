import { LedgerRow } from '../../components/ui'
import { money, plural } from '../../lib/format'
import type { Product } from '../../lib/types'

/** Un article écrit comme une ligne du cahier : nom · pointillés · prix, le détail dessous. */
export function StockRow({ product: x }: { product: Product }) {
  const quantity = x.is_unique_piece
    ? plural(x.quantity_on_hand, 'pièce')
    : `${x.quantity_on_hand} en stock`
  return (
    <LedgerRow
      className="stock-row"
      label={
        <>
          <span className="stock-row__name">{x.name}</span>
          {x.is_test && <span className="stock-row__test">test</span>}
        </>
      }
      meta={[x.category, x.brand, x.size, quantity].filter(Boolean).join(' · ')}
      value={<span className="figures">{money(Number(x.initial_sale_price))}</span>}
    />
  )
}
