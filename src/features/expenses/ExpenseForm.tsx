import { useState, type FormEvent } from 'react'
import { Button, Sheet } from '../../components/ui'
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
    <Sheet aria-label={editing ? 'Modifier la charge' : 'Ajouter une charge'}>
      <form className="form-grid" onSubmit={onSubmit}>
        <h2 className="form-grid__title">
          {editing ? 'Modifier la charge' : 'Ajouter une charge'}
        </h2>
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
            inputMode="numeric"
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
        <label className="form-check form-grid__full">
          <input name="recurring" type="checkbox" defaultChecked={editing?.recurring || false} />{' '}
          Charge récurrente
        </label>
        <div className="form-grid__actions">
          <Button variant="primary" type="submit" busy={busy} busyLabel="Enregistrement…">
            {editing ? 'Enregistrer les modifications' : 'Enregistrer la charge'}
          </Button>
          {editing && (
            <Button variant="ghost" onClick={onCancel}>
              Annuler
            </Button>
          )}
        </div>
      </form>
    </Sheet>
  )
}
