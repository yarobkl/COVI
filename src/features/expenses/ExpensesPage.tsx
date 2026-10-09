import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { Plus } from 'lucide-react'
import { localDay } from '../../lib/dates'
import { money } from '../../lib/format'
import {
  createExpense,
  deleteExpense,
  listExpenses,
  updateExpense,
  type Expense,
  type ExpenseInput,
} from '../../lib/operations'
import { ExpenseForm } from './ExpenseForm'
import { ExpenseRow } from './ExpenseRow'
import { ExpenseSummary } from './ExpenseSummary'

const today = () => localDay(new Date())

/** Shop running costs, kept separate from the arrival costs. */
export function ExpensesPage({ shopId }: { shopId: string }) {
  const [rows, setRows] = useState<Expense[]>([])
  const [show, setShow] = useState(false)
  const [editing, setEditing] = useState<Expense | null>(null)
  const [period, setPeriod] = useState<'month' | 'all'>('all')
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)
  const load = useCallback(
    () =>
      listExpenses(shopId)
        .then(setRows)
        .catch(() =>
          setMsg('Impossible de charger les charges. Vérifiez votre connexion puis réessayez.'),
        ),
    [shopId],
  )
  useEffect(() => {
    void load()
  }, [load])
  const visible = useMemo(
    () =>
      period === 'all'
        ? rows
        : rows.filter((x) => x.expense_date.slice(0, 7) === today().slice(0, 7)),
    [rows, period],
  )
  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const f = new FormData(e.currentTarget)
    const values: ExpenseInput = {
      category: String(f.get('category')),
      label: String(f.get('label') || '').trim(),
      amount: Number(f.get('amount')),
      expense_date: String(f.get('date')),
      recurring: f.get('recurring') === 'on',
    }
    if (!Number.isFinite(values.amount) || values.amount <= 0) {
      setMsg('Le montant doit être supérieur à zéro.')
      return
    }
    setBusy(true)
    setMsg('')
    try {
      if (editing) await updateExpense(shopId, editing.id, values)
      else await createExpense(shopId, values)
      setShow(false)
      setEditing(null)
      setMsg(editing ? 'Charge modifiée.' : 'Charge enregistrée.')
      await load()
    } catch {
      setMsg('Impossible d’enregistrer cette charge. Vérifiez les informations et votre connexion.')
    } finally {
      setBusy(false)
    }
  }
  function startEdit(row: Expense) {
    setEditing(row)
    setShow(true)
    setMsg('')
  }
  async function remove(row: Expense) {
    if (
      !window.confirm(
        `Supprimer la charge « ${row.label || row.category} » de ${money(Number(row.amount))} ?`,
      )
    )
      return
    try {
      await deleteExpense(shopId, row.id)
      setMsg('Charge supprimée.')
      await load()
    } catch {
      setMsg('Impossible de supprimer cette charge. Réessayez.')
    }
  }
  return (
    <div>
      <div className="hello">
        <div>
          <h1>Charges de la boutique</h1>
          <span>
            Dépenses réelles et charges de simulation marquées TEST, sans doubler les arrivages.
          </span>
        </div>
        <button
          onClick={() => {
            setEditing(null)
            setShow(!show)
            setMsg('')
          }}
        >
          <Plus />
          Ajouter une charge
        </button>
      </div>
      <ExpenseSummary visible={visible} period={period} />
      <section className="card expense-toolbar">
        <label>
          Période
          <select value={period} onChange={(e) => setPeriod(e.target.value as 'month' | 'all')}>
            <option value="month">Ce mois-ci</option>
            <option value="all">Tout l’historique</option>
          </select>
        </label>
      </section>
      {show && (
        <ExpenseForm
          editing={editing}
          today={today()}
          busy={busy}
          onSubmit={save}
          onCancel={() => {
            setEditing(null)
            setShow(false)
          }}
        />
      )}
      {msg && <p className="successmsg">{msg}</p>}
      <section className="card">
        {visible.length === 0 ? (
          <p>Aucune charge sur cette période.</p>
        ) : (
          visible.map((x) => (
            <ExpenseRow
              key={x.id}
              expense={x}
              onEdit={() => startEdit(x)}
              onDelete={() => void remove(x)}
            />
          ))
        )}
      </section>
    </div>
  )
}
