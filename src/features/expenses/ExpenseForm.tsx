import type { FormEvent } from 'react'
import type { Expense } from '../../lib/operations'
import { expenseCategories } from './expenseCategories'

/** Creates an expense, or edits `editing` when set. */
export function ExpenseForm({
  editing,
  today,
  busy,
  onSubmit,
  onCancel,
}: {
  editing: Expense | null
  today: string
  busy: boolean
  onSubmit: (e: FormEvent<HTMLFormElement>) => void
  onCancel: () => void
}) {
  return (
    <form className="card formgrid" onSubmit={onSubmit}>
      <div className="span2">
        <h2>{editing ? 'Modifier la charge' : 'Ajouter une charge'}</h2>
      </div>
      <label>
        Catégorie
        <select name="category" defaultValue={editing?.category || 'Loyer'}>
          {expenseCategories.map((x) => (
            <option key={x}>{x}</option>
          ))}
        </select>
      </label>
      <label>
        Libellé
        <input name="label" defaultValue={editing?.label || ''} />
      </label>
      <label>
        Montant
        <input
          name="amount"
          type="number"
          min="1"
          step="1"
          required
          defaultValue={editing?.amount}
        />
      </label>
      <label>
        Date
        <input name="date" type="date" required defaultValue={editing?.expense_date || today} />
      </label>
      <label className="span2">
        <span>
          <input name="recurring" type="checkbox" defaultChecked={editing?.recurring || false} />{' '}
          Charge récurrente
        </span>
      </label>
      <button className="primary span2" disabled={busy}>
        {busy
          ? 'Enregistrement…'
          : editing
            ? 'Enregistrer les modifications'
            : 'Enregistrer la charge'}
      </button>
      {editing && (
        <button className="outline span2" type="button" onClick={onCancel}>
          Annuler
        </button>
      )}
    </form>
  )
}
