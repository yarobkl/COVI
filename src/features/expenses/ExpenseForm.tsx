import { useState, type FormEvent } from 'react'
import { ChoiceField } from '../../components/ui/ChoiceField'
import type { Expense } from '../../lib/types'
import { expenseCategories } from './expenseCategories'

/** Creates an expense, or edits `editing` when set. */
export function ExpenseForm({
  editing,
  usedLabels,
  today,
  busy,
  onSubmit,
  onCancel,
}: {
  editing: Expense | null
  usedLabels: { category: string; label: string }[]
  today: string
  busy: boolean
  onSubmit: (e: FormEvent<HTMLFormElement>) => void
  onCancel: () => void
}) {
  const [category, setCategory] = useState(editing?.category || 'Loyer')
  const suggestions = [
    category,
    ...usedLabels.filter((item) => item.category === category).map((item) => item.label),
  ]
  return (
    <form className="card formgrid" onSubmit={onSubmit}>
      <div className="span2">
        <h2>{editing ? 'Modifier la charge' : 'Ajouter une charge'}</h2>
      </div>
      <label>
        Catégorie
        <select name="category" value={category} onChange={(e) => setCategory(e.target.value)}>
          {expenseCategories.map((x) => (
            <option key={x}>{x}</option>
          ))}
        </select>
      </label>
      <label>
        Libellé
        <ChoiceField
          key={category}
          name="label"
          choices={suggestions}
          defaultValue={category === editing?.category ? editing?.label : ''}
          prompt="Choisir un libellé (facultatif)"
          otherLabel="Ajouter un libellé"
          customPlaceholder="Nouveau libellé"
        />
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
