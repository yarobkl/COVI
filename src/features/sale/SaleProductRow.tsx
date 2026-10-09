import { ProductThumb } from '../../components/ProductThumb'
import type { Product } from '../../lib/types'
import { money, plural } from '../../lib/format'

export function SaleProductRow({
  product: x,
  onSelect,
}: {
  product: Product
  onSelect: () => void
}) {
  return (
    <div className="row">
      <ProductThumb imageUrl={x.image_url} fallback={x.name[0]} />
      <div className="grow">
        <b>
          {x.name} {x.is_test && <em className="test-tag">TEST</em>}
        </b>
        <span>
          {money(Number(x.initial_sale_price))} · {plural(x.quantity_on_hand, 'disponible')}
        </span>
      </div>
      <button className="add" onClick={onSelect}>
        +
      </button>
    </div>
  )
}
