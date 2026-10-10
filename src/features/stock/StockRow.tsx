import { Amount } from '../../components/ui'
import type { Product } from '../../lib/types'
import '../../styles/app/stock.css'
import { stockNote } from '../sale/saleMath'
import { productDetails } from './stockFilters'

/** Photo of the article, or its initial written in cash-register figures. */
export function ProductPicture({
  product,
  size = 'md',
}: {
  product: Pick<Product, 'name' | 'image_url'>
  size?: 'sm' | 'md'
}) {
  return (
    <span className={`product-pic product-pic--${size}`} aria-hidden="true">
      {product.image_url ? (
        <img src={product.image_url} alt="" loading="lazy" />
      ) : (
        product.name.trim().charAt(0).toLocaleUpperCase('fr-FR')
      )}
    </span>
  )
}

/**
 * One line of the stock notebook: photo or initial, name, type · brand · size, where it came
 * from, the displayed price and what is left (« Plus que 1 » under the highlighter).
 */
export function StockRow({ product, arrivalCode }: { product: Product; arrivalCode?: string }) {
  const stock = stockNote(product)
  const details = productDetails(product)
  return (
    <li className="stock-row">
      <ProductPicture product={product} />
      <div className="stock-row__main">
        <p className="stock-row__name">{product.name}</p>
        {details && <p className="stock-row__meta">{details}</p>}
        <p className="stock-row__meta">
          {stock.low ? <mark>{stock.text}</mark> : stock.text}
          {arrivalCode && (
            <>
              {' · '}
              <span className="stock-row__code">{arrivalCode}</span>
            </>
          )}
          {product.is_test && ' · exemple'}
        </p>
      </div>
      <p className="stock-row__price">
        <span className="visually-hidden">Prix affiché : </span>
        <Amount value={Number(product.initial_sale_price)} />
      </p>
    </li>
  )
}
