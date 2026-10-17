import { LedgerRow } from '../../components/ui'
import { money, plural } from '../../lib/format'
import type { Product } from '../../lib/types'

/**
 * Un article écrit comme une ligne du cahier : nom · pointillés · prix, le détail dessous. Toucher
 * la ligne ouvre « Modifier le produit ».
 */
export function StockRow({ product: x, onOpen }: { product: Product; onOpen?: () => void }) {
  const quantity = x.is_unique_piece
    ? plural(x.quantity_on_hand, 'pièce')
    : `${x.quantity_on_hand} en stock`
  const name = (
    <>
      <span className="stock-row__name">{x.name}</span>
      {x.is_test && <span className="test-note">test</span>}
    </>
  )
  return (
    <LedgerRow
      className="stock-row"
      variant={onOpen ? 'link' : undefined}
      label={
        onOpen ? (
          <button
            type="button"
            className="ledger__open"
            aria-label={`Modifier ${x.name}`}
            onClick={onOpen}
          >
            {name}
          </button>
        ) : (
          name
        )
      }
      meta={[x.category, x.brand, x.size, quantity].filter(Boolean).join(' · ')}
      value={<span className="figures">{money(Number(x.initial_sale_price))}</span>}
    />
  )
}
