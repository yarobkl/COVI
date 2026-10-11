import { cx } from '../../components/ui'
import { fcfa, money } from '../../lib/format'
import type { Product } from '../../lib/types'
import { stockNote } from './saleMath'

/**
 * One article at the counter: a big key (photo or initial, name, what is left, price). Touching it
 * puts the article in the cart; the count in the cart pops on its corner.
 */
export function SaleTile({
  product,
  arrivalCode,
  inCart,
  onAdd,
  locked,
}: {
  product: Product
  arrivalCode?: string
  /** How many of this article are in the cart (0: none). */
  inCart: number
  onAdd: () => void
  /** Read only (subscription suspended): the article stays visible but cannot be sold. */
  locked?: { reasonId: string }
}) {
  const stock = stockNote(product)
  const price = Number(product.initial_sale_price)
  return (
    <button
      type="button"
      className={cx('sale-tile', 'sale-tile--thumb', inCart > 0 && 'sale-tile--in')}
      disabled={stock.out || Boolean(locked)}
      aria-describedby={locked?.reasonId}
      data-locked={locked ? 'true' : undefined}
      aria-label={`Ajouter ${product.name} au panier, ${money(price)}, ${stock.text.toLowerCase()}${inCart > 0 ? `, déjà ${inCart} dans le panier` : ''}`}
      onClick={onAdd}
    >
      {inCart > 0 && (
        // Keyed by the count: the badge pops again at each touch.
        <span key={inCart} className="sale-tile__count" aria-hidden="true">
          {inCart}
        </span>
      )}
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
