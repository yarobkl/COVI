import type { FormEvent } from 'react'
import type { Arrival } from '../../lib/operations'

/** Adds a product to a received arrival (a single piece for a balloon). */
export function ArrivalProductForm({
  arrival,
  onSubmit,
  onCancel,
}: {
  arrival: Arrival
  onSubmit: (e: FormEvent<HTMLFormElement>) => void
  onCancel: () => void
}) {
  return (
    <form className="card formgrid" onSubmit={onSubmit}>
      <div className="span2">
        <small>AJOUT À {arrival.code}</small>
        <h2>
          {arrival.kind === 'balloon'
            ? 'Nouvelle pièce du ballon'
            : 'Nouvelle référence fournisseur'}
        </h2>
      </div>
      <label>
        Produit
        <input name="name" required />
      </label>
      <label>
        Photo
        <input name="image" type="file" accept="image/jpeg,image/png,image/webp" />
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
        <input name="price" type="number" min="1" required />
      </label>
      {arrival.kind === 'supplier_order' && (
        <label>
          Quantité
          <input name="quantity" type="number" min="1" defaultValue="1" required />
        </label>
      )}
      <button className="primary">Ajouter au stock</button>
      <button type="button" className="outline" onClick={onCancel}>
        Annuler
      </button>
    </form>
  )
}
