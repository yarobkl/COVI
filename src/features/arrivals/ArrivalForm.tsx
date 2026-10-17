import type { FormEvent } from 'react'
import { Button, Sheet } from '../../components/ui'
import { ChoiceField } from '../../components/ui/ChoiceField'
import { arrivalCountrySuggestions } from '../../lib/countries'
import { localDay } from '../../lib/dates'
import type { Arrival } from '../../lib/types'

/** New arrival (supplier order or balloon), created as a draft. */
export function ArrivalForm({
  kind,
  arrivalKind,
  suppliers,
  onArrivalKindChange,
  busy,
  onSubmit,
}: {
  /** Kind imposed by the page ("Mes commandes" / "Mes ballons"); chosen in the form otherwise. */
  kind?: Arrival['kind']
  arrivalKind: Arrival['kind']
  suppliers: string[]
  onArrivalKindChange: (kind: Arrival['kind']) => void
  busy: boolean
  onSubmit: (e: FormEvent<HTMLFormElement>) => void
}) {
  return (
    <Sheet aria-label="Nouvel arrivage">
      <form className="form-grid" onSubmit={onSubmit}>
        <h2 className="form-grid__title">Nouvel arrivage</h2>
        {!kind && (
          <label>
            Type d’arrivage
            <select
              name="kind"
              value={arrivalKind}
              onChange={(e) => onArrivalKindChange(e.target.value as Arrival['kind'])}
            >
              <option value="supplier_order">Commande fournisseur</option>
              <option value="balloon">Ballon / lot mixte</option>
            </select>
          </label>
        )}
        <label>
          Pays d'origine
          <select name="country" required defaultValue="">
            <option value="">Choisir un pays</option>
            {arrivalCountrySuggestions.map((c) => (
              <option key={c.name} value={c.name}>
                {c.flag} {c.name}
              </option>
            ))}
          </select>
        </label>
        {arrivalKind === 'supplier_order' && (
          <>
            <label>
              Fournisseur
              <ChoiceField
                name="supplier"
                choices={suppliers}
                required
                prompt="Choisir un fournisseur"
                otherLabel="Ajouter un nouveau fournisseur"
                customPlaceholder="Nom du nouveau fournisseur"
              />
            </label>
            <label>
              Date de commande
              <input name="orderDate" type="date" defaultValue={localDay(new Date())} />
            </label>
            <label>
              Coût marchandises
              <input
                name="goods"
                type="number"
                inputMode="numeric"
                min="0"
                step="1"
                defaultValue="0"
              />
            </label>
            <label>
              Transport
              <input
                name="transport"
                type="number"
                inputMode="numeric"
                min="0"
                step="1"
                defaultValue="0"
              />
            </label>
            <label>
              Douane
              <input
                name="customs"
                type="number"
                inputMode="numeric"
                min="0"
                step="1"
                defaultValue="0"
              />
            </label>
          </>
        )}
        {arrivalKind === 'balloon' && (
          <label>
            Coût global du ballon
            <input name="global" type="number" inputMode="numeric" min="1" step="1" required />
          </label>
        )}
        <p className="form-grid__note">
          Le nouvel arrivage commencera en brouillon. Vous pourrez ensuite le faire avancer jusqu’à
          la réception.
        </p>
        <div className="form-grid__actions">
          <Button variant="primary" type="submit" busy={busy} busyLabel="Enregistrement…">
            Créer le brouillon
          </Button>
        </div>
      </form>
    </Sheet>
  )
}
