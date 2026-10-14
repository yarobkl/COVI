import type { FormEvent } from 'react'
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
    <form className="card formgrid" onSubmit={onSubmit}>
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
            <input name="goods" type="number" min="0" step="1" defaultValue="0" />
          </label>
          <label>
            Transport
            <input name="transport" type="number" min="0" step="1" defaultValue="0" />
          </label>
          <label>
            Douane
            <input name="customs" type="number" min="0" step="1" defaultValue="0" />
          </label>
        </>
      )}
      {arrivalKind === 'balloon' && (
        <label>
          Coût global du ballon
          <input name="global" type="number" min="1" step="1" required />
        </label>
      )}
      <div className="span2">
        Le nouvel arrivage commencera en brouillon. Vous pourrez ensuite le faire avancer jusqu’à la
        réception.
      </div>
      <button className="primary span2" disabled={busy}>
        {busy ? 'Enregistrement…' : 'Créer le brouillon'}
      </button>
    </form>
  )
}
