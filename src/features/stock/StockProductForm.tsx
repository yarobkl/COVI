import type { FormEvent } from 'react'
import { ChoiceField } from '../../components/ui/ChoiceField'
import { productChoices } from '../../lib/productChoices'
import type { Arrival, Product } from '../../lib/types'

/** Adds a product to the stock, optionally attached to an arrival. */
export function StockProductForm({
  arrivals,
  products,
  onSubmit,
}: {
  arrivals: Arrival[]
  products: Product[]
  onSubmit: (e: FormEvent<HTMLFormElement>) => void
}) {
  const choices = productChoices(products)
  return (
    <form className="card formgrid" onSubmit={onSubmit}>
      <label>
        Produit
        <ChoiceField name="name" choices={choices.names} required prompt="Choisir un article" otherLabel="Créer un nouvel article" />
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
