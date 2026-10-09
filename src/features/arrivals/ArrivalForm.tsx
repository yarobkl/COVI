import type { FormEvent } from 'react'
import { countries } from '../../lib/countries'
import { localDay } from '../../lib/dates'
import type { Arrival } from '../../lib/operations'

/** New arrival (supplier order or balloon), created as a draft. */
export function ArrivalForm({
  kind,
  arrivalKind,
  onArrivalKindChange,
  busy,
  onSubmit,
}: {
  /** Kind imposed by the page ("Mes commandes" / "Mes ballons"); chosen in the form otherwise. */
  kind?: Arrival['kind']
  arrivalKind: Arrival['kind']
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
        <input name="country" list="covi-countries" required placeholder="Rechercher un pays…" />
        <datalist id="covi-countries">
          {countries.map((c) => (
            <option key={c.code} value={c.name}>
              {c.flag} {c.name}
            </option>
          ))}
        </datalist>
      </label>
      {arrivalKind === 'supplier_order' && (
        <>
          <label>
            Fournisseur
            <input name="supplier" placeholder="Nom du fournisseur" required />
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
