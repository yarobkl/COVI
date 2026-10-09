import { ProductThumb } from '../../components/ProductThumb'
import type { Product } from '../../lib/types'
import { money, plural } from '../../lib/format'

export function StockRow({ product: x }: { product: Product }) {
  return (
    <div className="row">
      <ProductThumb imageUrl={x.image_url} fallback={x.name[0]} />
      <div className="grow">
        <b>
          {x.name} {x.is_test && <em className="test-tag">TEST</em>}
        </b>
        <span>{[x.category, x.brand, x.size].filter(Boolean).join(' · ')}</span>
      </div>
      <b>{money(Number(x.initial_sale_price))}</b>
      <span className="qty">
        {x.is_unique_piece ? plural(x.quantity_on_hand, 'pièce') : x.quantity_on_hand + ' en stock'}
      </span>
    </div>
  )
}
