import type { FormEvent } from 'react'
import type { Arrival } from '../../lib/types'

/** Adds a product to the stock, optionally attached to an arrival. */
export function StockProductForm({
  arrivals,
  onSubmit,
}: {
  arrivals: Arrival[]
  onSubmit: (e: FormEvent<HTMLFormElement>) => void
}) {
  return (
    <form className="card formgrid" onSubmit={onSubmit}>
      <label>
        Produit
        <input name="name" required />
      </label>
      <label>
        Photo
        <input name="image" type="file" accept="image/jpeg,image/png,image/webp" />
      </label>
      <label>
        Arrivage
        <select name="arrival">
          <option value="">Sans arrivage</option>
          {arrivals.map((a) => (
            <option key={a.id} value={a.id}>
              {a.code} · {a.kind === 'balloon' ? 'Ballon' : a.supplier_name || 'Commande'}
            </option>
          ))}
        </select>
      </label>
      <label>
        Catégorie
        <input name="category" />
      </label>
      <label>
        Marque
        <input name="brand" />
      </label>
      <label>
        Taille
        <input name="size" />
      </label>
      <label>
        Prix de vente initial
        <input name="price" type="number" min="0" required />
      </label>
      <label>
        Quantité
        <input name="quantity" type="number" min="1" defaultValue="1" />
      </label>
      <label className="span2">
        <input name="unique" type="checkbox" /> Pièce unique (ballon / lot mixte)
      </label>
      <button className="primary span2">Ajouter au stock</button>
    </form>
  )
}
