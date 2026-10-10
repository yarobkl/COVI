import { cx } from '../../components/ui'
import { fcfa, money } from '../../lib/format'
import type { Product } from '../../lib/types'
import { stockNote } from './saleMath'

/** One article at the counter: a big key (photo or initial, name, what is left, price). */
export function SaleTile({
  product,
  arrivalCode,
  selected,
  onSelect,
  locked,
}: {
  product: Product
  arrivalCode?: string
  selected: boolean
  onSelect: () => void
  /** Read only (subscription suspended): the article stays visible but cannot be sold. */
  locked?: { reasonId: string }
}) {
  const stock = stockNote(product)
  const price = Number(product.initial_sale_price)
  return (
    <button
      type="button"
      className={cx('sale-tile', 'sale-tile--thumb', selected && 'sale-tile--in')}
      disabled={stock.out || Boolean(locked)}
      aria-describedby={locked?.reasonId}
      data-locked={locked ? 'true' : undefined}
      aria-pressed={selected}
      aria-label={`Vendre ${product.name}, ${money(price)}, ${stock.text.toLowerCase()}`}
      onClick={onSelect}
    >
      <span className="sale-tile__thumb" aria-hidden="true">
        {product.image_url ? (
          <img src={product.image_url} alt="" loading="lazy" />
        ) : (
          product.name.trim().charAt(0).toLocaleUpperCase('fr-FR')
        )}
      </span>
      <span className="sale-tile__name">{product.name}</span>
      <span className="sale-tile__meta">
        {stock.low ? <mark>{stock.text}</mark> : stock.text}
        {arrivalCode && ` · ${arrivalCode}`}
        {product.is_test && ' · exemple'}
      </span>
      <span className="sale-tile__price">{fcfa(price)}</span>
    </button>
  )
}
