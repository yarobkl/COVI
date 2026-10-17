import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { PlusIcon } from '../../components/icons'
import { Button, Ledger, PageHead, PageMessage, Segmented, Sheet } from '../../components/ui'
import { localDay } from '../../lib/dates'
import { money } from '../../lib/format'
import {
  createExpense,
  deleteExpense,
  listExpenses,
  updateExpense,
  type ExpenseInput,
} from '../../lib/operations'
import type { Expense } from '../../lib/types'
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
    <div className="page-stack">
      <PageHead
        title="Charges de la boutique"
        sub="Loyer, transport, salaires… Les coûts des arrivages sont comptés à part."
        action={
          <Button
            variant="secondary"
            icon={<PlusIcon />}
            onClick={() => {
              setEditing(null)
              setShow(!show)
              setMsg('')
            }}
          >
            {show && !editing ? 'Fermer' : 'Ajouter une charge'}
          </Button>
        }
      />
      {show && (
        <ExpenseForm
          key={editing?.id ?? 'new'}
          editing={editing}
          usedLabels={rows.map((item) => ({ category: item.category, label: item.label ?? '' }))}
          today={today()}
          busy={busy}
          onSubmit={save}
          onCancel={() => {
            setEditing(null)
            setShow(false)
          }}
        />
      )}
      {msg && <PageMessage>{msg}</PageMessage>}
      <Sheet aria-label="Charges">
        <Segmented
          legend="Période"
          value={period}
          onChange={setPeriod}
          options={[
            { value: 'month' as const, label: 'Ce mois-ci' },
            { value: 'all' as const, label: 'Tout l’historique' },
          ]}
        />
        {visible.length === 0 ? (
          <p className="muted">Aucune charge sur cette période.</p>
        ) : (
          <Ledger label="Charges, la plus récente d’abord">
            {visible.map((x) => (
              <ExpenseRow
                key={x.id}
                expense={x}
                onEdit={() => startEdit(x)}
                onDelete={() => void remove(x)}
              />
            ))}
          </Ledger>
        )}
        <ExpenseSummary visible={visible} period={period} />
      </Sheet>
    </div>
  )
}
