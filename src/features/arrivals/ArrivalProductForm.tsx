import type { FormEvent } from 'react'
import { ChoiceField } from '../../components/ui/ChoiceField'
import { productChoices } from '../../lib/productChoices'
import type { Arrival, Product } from '../../lib/types'

/** Adds a product to a received arrival (a single piece for a balloon). */
export function ArrivalProductForm({
  arrival,
  products,
  onSubmit,
  onCancel,
}: {
  arrival: Arrival
  products: Product[]
  onSubmit: (e: FormEvent<HTMLFormElement>) => void
  onCancel: () => void
}) {
  const choices = productChoices(products)
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
        <ChoiceField name="name" choices={choices.names} required prompt="Choisir un article" otherLabel="Créer un nouvel article" />
      </label>
      <label>
        Photo
        <input name="image" type="file" accept="image/jpeg,image/png,image/webp" />
      </label>
      <label>
        Catégorie
        <ChoiceField name="category" choices={choices.categories} prompt="Choisir une catégorie" otherLabel="Nouvelle catégorie" />
      </label>
      <label>
        Marque
        <ChoiceField name="brand" choices={choices.brands} prompt="Choisir une marque" otherLabel="Nouvelle marque" />
      </label>
      <label>
        Taille
        <ChoiceField name="size" choices={choices.sizes} prompt="Choisir une taille" otherLabel="Autre taille" />
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
