import type { Product } from '../../lib/covi'
import { money, paymentLabels } from '../../lib/format'

/** Current sale: sold price, quantity, payment method and validation. */
export function Checkout({
  selected,
  price,
  onPriceChange,
  qty,
  onQtyChange,
  pay,
  onPayChange,
  busy,
  msg,
  onSell,
}: {
  selected: Product | null
  price: string
  onPriceChange: (price: string) => void
  qty: number
  onQtyChange: (qty: number) => void
  pay: string
  onPayChange: (pay: string) => void
  busy: boolean
  msg: string
  onSell: () => void
}) {
  return (
    <section className="card checkout">
      <small>VENTE EN COURS</small>
      {selected ? (
        <>
          <h2>{selected.name}</h2>
          <p>Prix initial : {money(Number(selected.initial_sale_price))}</p>
          <label className="sellprice">
            Prix vendu (FCFA)
            <input
              type="number"
              min="0"
              value={price}
              onChange={(e) => onPriceChange(e.target.value)}
            />
          </label>
          {!selected.is_unique_piece && (
            <label className="sellprice">
              Quantité
              <input
                type="number"
                min="1"
                max={selected.quantity_on_hand}
                value={qty}
                onChange={(e) => onQtyChange(Number(e.target.value))}
              />
            </label>
          )}
          <div className="payments">
            {paymentLabels.map((x) => (
              <button
                className={pay === x ? 'payactive' : ''}
                onClick={() => onPayChange(x)}
                key={x}
              >
                {x}
              </button>
            ))}
          </div>
        </>
      ) : (
        <>
          <h2>Panier vide</h2>
          <p>Sélectionnez un produit.</p>
        </>
      )}
      <div className="total">
        <span>Total</span>
        <b>{price ? money(Number(price) * qty) : '0 FCFA'}</b>
      </div>
      <button className="primary" disabled={!selected || !price || busy} onClick={onSell}>
        {busy ? 'Enregistrement…' : 'Valider la vente'}
      </button>
      {msg && <p className="successmsg">{msg}</p>}
    </section>
  )
}
