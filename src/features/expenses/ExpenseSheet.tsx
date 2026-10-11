import { useId, useState, type FormEvent } from 'react'
import { AmountInput, Button, Dialog, Field, Input } from '../../components/ui'
import { Switch } from '../../components/ui/Switch'
import { fcfa, parseAmount } from '../../lib/format'
import type { ExpenseInput } from '../../lib/operations'
import type { Expense } from '../../lib/types'
import { categoryLabel, expenseCategories } from './expenseCategories'
import { draftOf, expenseSaveError, readDraft, type ExpenseDraft } from './expenseForm'

/**
 * « Nouvelle charge » / « Modifier », in a sheet that rises from the bottom on phones. `save`
 * throws when the network does not answer: the sheet stays open with the message.
 */
export function ExpenseSheet({
  open,
  editing,
  today,
  onClose,
  save,
  onDelete,
}: {
  open: boolean
  editing: Expense | null
  today: string
  onClose: () => void
  save: (input: ExpenseInput) => Promise<void>
  /** Only when changing a charge: asks to delete it. */
  onDelete?: () => void
}) {
  const titleId = useId()
  return (
    <Dialog open={open} onClose={onClose} labelledBy={titleId} sheet>
      {/* A new form each time the sheet opens on another charge. */}
      <ExpenseForm
        key={editing?.id ?? 'new'}
        titleId={titleId}
        editing={editing}
        today={today}
        onClose={onClose}
        save={save}
        onDelete={onDelete}
      />
    </Dialog>
  )
}

function ExpenseForm({
  titleId,
  editing,
  today,
  onClose,
  save,
  onDelete,
}: {
  titleId: string
  editing: Expense | null
  today: string
  onClose: () => void
  save: (input: ExpenseInput) => Promise<void>
  onDelete?: () => void
}) {
  const [draft, setDraft] = useState<ExpenseDraft>(() => draftOf(editing, today))
  const [errors, setErrors] = useState<{ amount?: string; date?: string }>({})
  const [failure, setFailure] = useState('')
  const [busy, setBusy] = useState(false)
  const set = <K extends keyof ExpenseDraft>(key: K, value: ExpenseDraft[K]) =>
    setDraft((d) => ({ ...d, [key]: value }))
  // An old category (« Sacs ») is shown with its new name, and stays selectable.
  const categories: string[] = [...expenseCategories]
  if (!categories.includes(draft.category)) categories.unshift(draft.category)

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const read = readDraft(draft)
    if ('error' in read) {
      setErrors({ [read.field]: read.error })
      return
    }
    setErrors({})
    setFailure('')
    setBusy(true)
    try {
      await save(read.input)
    } catch (err) {
      setFailure(expenseSaveError(err, editing ? 'edit' : 'new'))
    } finally {
      setBusy(false)
    }
  }

  return (
    <form className="dialog__body expense-form" onSubmit={(e) => void submit(e)} noValidate>
      <h2 className="dialog__title" id={titleId}>
        {editing ? `Modifier : ${categoryLabel(editing.category)}` : 'Nouvelle charge'}
      </h2>
      <Field label="C’est pour quoi ?">
        {(control) => (
          <select
            {...control}
            className="select"
            value={draft.category}
            onChange={(e) => set('category', e.target.value)}
          >
            {categories.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        )}
      </Field>
      <Field label="Montant (FCFA)" error={errors.amount}>
        {(control) => (
          <AmountInput
            {...control}
            value={draft.amount ? fcfa(parseAmount(draft.amount) ?? 0) : ''}
            onChange={(e) => set('amount', e.target.value)}
            placeholder="0"
          />
        )}
      </Field>
      <Field label="Payé le" error={errors.date}>
        {(control) => (
          <Input
            {...control}
            type="date"
            value={draft.date}
            max="2100-12-31"
            onChange={(e) => set('date', e.target.value)}
          />
        )}
      </Field>
      <Field label="Précision" optional>
        {(control) => (
          <Input
            {...control}
            value={draft.label}
            maxLength={120}
            placeholder="Ex. loyer d’octobre"
            onChange={(e) => set('label', e.target.value)}
          />
        )}
      </Field>
      <Switch checked={draft.recurring} onChange={(v) => set('recurring', v)}>
        Revient chaque mois
      </Switch>
      {failure && (
        <p className="field__error" role="alert">
          {failure}
        </p>
      )}
      <div className="dialog__actions">
        <Button variant="secondary" onClick={onClose}>
          Annuler
        </Button>
        <Button write variant="primary" type="submit" busy={busy}>
          {editing ? 'Enregistrer' : 'Noter la charge'}
        </Button>
      </div>
      {editing && onDelete && (
        <div className="expense-form__delete">
          <Button variant="danger" onClick={onDelete}>
            Supprimer cette charge
          </Button>
        </div>
      )}
    </form>
  )
}
