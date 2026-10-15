import type { FormEvent } from 'react'
import { Button, Sheet } from '../../components/ui'
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
    <Sheet aria-label={`Ajout à ${arrival.code}`}>
      <form className="form-grid" onSubmit={onSubmit}>
        <h2 className="form-grid__title">
          <span className="form-grid__kicker">Ajout à {arrival.code}</span>
          {arrival.kind === 'balloon'
            ? 'Nouvelle pièce du ballon'
            : 'Nouvelle référence fournisseur'}
        </h2>
        <label>
          Produit
          <ChoiceField
            name="name"
            choices={choices.names}
            required
            prompt="Choisir un article"
            otherLabel="Créer un nouvel article"
          />
        </label>
        <label>
          Catégorie
          <ChoiceField
            name="category"
            choices={choices.categories}
            prompt="Choisir une catégorie"
            otherLabel="Nouvelle catégorie"
          />
        </label>
        <label>
          Marque
          <ChoiceField
            name="brand"
            choices={choices.brands}
            prompt="Choisir une marque"
            otherLabel="Nouvelle marque"
          />
        </label>
        <label>
          Taille
          <ChoiceField
            name="size"
            choices={choices.sizes}
            prompt="Choisir une taille"
            otherLabel="Autre taille"
          />
        </label>
        <label>
          Prix de vente initial
          <input name="price" type="number" inputMode="numeric" min="1" required />
        </label>
        {arrival.kind === 'supplier_order' && (
          <label>
            Quantité
            <input name="quantity" type="number" min="1" defaultValue="1" required />
          </label>
        )}
        <div className="form-grid__actions">
          <Button variant="primary" type="submit">
            Ajouter au stock
          </Button>
          <Button variant="ghost" onClick={onCancel}>
            Annuler
          </Button>
        </div>
      </form>
    </Sheet>
  )
}
