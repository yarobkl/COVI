import { useCallback, useId, useMemo, useState } from 'react'
import { CloudOffIcon, PlusIcon } from '../../components/icons'
import { Button, Dialog, EmptyState, Notice, Skeleton } from '../../components/ui'
import { FilterChips } from '../../components/ui/FilterChips'
import { MonthNav } from '../../components/ui/MonthNav'
import { useAsyncData } from '../../hooks/useAsyncData'
import { localDay, localMonth } from '../../lib/dates'
import { money } from '../../lib/format'
import {
  createExpense,
  deleteExpense,
  listExpenses,
  updateExpense,
  type ExpenseInput,
} from '../../lib/operations'
import type { Expense } from '../../lib/types'
import '../../styles/app/charges.css'
import { categoryLabel } from './expenseCategories'
import { ExpenseLedger, ExpensesHero, type ExpenseView } from './ExpenseLedger'
import {
  byMonth,
  expenseMonth,
  expensesOfMonth,
  monthRange,
  monthSteps,
  monthTitle,
} from './expenseMonths'
import { ExpenseSheet } from './ExpenseSheet'

const views = [
  { value: 'month', label: 'Mois par mois' },
  { value: 'all', label: 'Depuis le début' },
] as const

/**
 * Charges de la boutique: the month's charges in red notebook lines, its total, and the sheet to
 * note, change or delete one. The purchase of goods belongs to Arrivages, not here.
 */
export function ExpensesPage({ shopId }: { shopId: string }) {
  const load = useCallback(() => listExpenses(shopId), [shopId])
  const { data, error, retry } = useAsyncData(load)
  // Changes made here are applied at once, without reloading the list.
  const [local, setLocal] = useState<{ from: Expense[]; rows: Expense[] } | null>(null)
  const rows = useMemo(
    () => (local && local.from === data ? local.rows : (data ?? [])),
    [local, data],
  )
  const setRows = (next: Expense[]) => data && setLocal({ from: data, rows: next })

  const [now] = useState(() => new Date())
  const [view, setView] = useState<ExpenseView>('month')
  const [month, setMonth] = useState(() => localMonth(now))
  const [sheet, setSheet] = useState<{ editing: Expense | null } | null>(null)
  const [toDelete, setToDelete] = useState<Expense | null>(null)
  const [done, setDone] = useState('')

  const range = useMemo(() => monthRange(rows, now), [rows, now])
  const steps = monthSteps(month, range)
  const visible = useMemo(
    () =>
      view === 'month' ? [{ key: month, expenses: expensesOfMonth(rows, month) }] : byMonth(rows),
    [view, month, rows],
  )

  async function save(input: ExpenseInput) {
    const editing = sheet?.editing ?? null
    const saved = (
      editing ? await updateExpense(shopId, editing.id, input) : await createExpense(shopId, input)
    ) as Expense
    setRows(editing ? rows.map((r) => (r.id === saved.id ? saved : r)) : [saved, ...rows])
    setSheet(null)
    setMonth(expenseMonth(saved))
    const name = categoryLabel(saved.category)
    setDone(editing ? `${name} modifié.` : `${name} : ${money(Number(saved.amount))} noté.`)
  }

  async function remove(expense: Expense) {
    await deleteExpense(shopId, expense.id)
    setRows(rows.filter((r) => r.id !== expense.id))
    setToDelete(null)
    setSheet(null)
    setDone('Charge supprimée.')
  }

  const open = (editing: Expense | null) => {
    setDone('')
    setSheet({ editing })
  }

  return (
    <div className="charges-page">
      <header className="page-head">
        <div>
          <h1>Charges de la boutique</h1>
          <p className="page-head__sub">
            Ce que la boutique paie pour tourner. L’achat de marchandise se note dans{' '}
            <a href="#/arrivages">Arrivages</a>.
          </p>
        </div>
        <Button variant="primary" icon={<PlusIcon />} onClick={() => open(null)}>
          Noter une charge
        </Button>
      </header>

      {done && (
        <Notice tone="success" className="charges-done">
          <p>{done}</p>
        </Notice>
      )}

      {error ? (
        <Notice
          icon={CloudOffIcon}
          title="Les charges ne s’affichent pas : pas de réseau."
          actions={
            <Button variant="secondary" onClick={retry}>
              Réessayer
            </Button>
          }
        >
          <p>Réessayez dans un instant.</p>
        </Notice>
      ) : !data ? (
        <Skeleton caption="On fait les comptes…" />
      ) : (
        <>
          <div className="charges-filters">
            <FilterChips
              legend="Afficher"
              hideLegend
              options={views}
              value={view}
              onChange={setView}
            />
            {view === 'month' && (
              <MonthNav
                current={monthTitle(month, now)}
                previous={
                  steps.previous
                    ? {
                        label: monthTitle(steps.previous, now),
                        onClick: () => setMonth(steps.previous!),
                      }
                    : undefined
                }
                next={
                  steps.next
                    ? { label: monthTitle(steps.next, now), onClick: () => setMonth(steps.next!) }
                    : undefined
                }
              />
            )}
          </div>

          <ExpensesHero
            view={view}
            month={month}
            now={now}
            rows={visible.flatMap((m) => m.expenses)}
          />

          {visible.every((m) => m.expenses.length === 0) ? (
            <EmptyState
              title={
                view === 'month'
                  ? `Aucune charge notée en ${monthTitle(month, now)}.`
                  : 'Aucune charge notée pour l’instant.'
              }
              actions={
                <Button variant="primary" icon={<PlusIcon />} onClick={() => open(null)}>
                  Noter une charge
                </Button>
              }
            >
              <p>
                Loyer, électricité, sacs, frais Mobile Money… tout ce qui fait tourner la boutique.
              </p>
            </EmptyState>
          ) : (
            visible.map((m) => (
              <ExpenseLedger
                key={m.key}
                title={view === 'all' ? monthTitle(m.key, now) : undefined}
                totalLabel={`Total ${view === 'all' || m.key !== localMonth(now) ? `de ${monthTitle(m.key, now)}` : 'du mois'}`}
                expenses={m.expenses}
                onEdit={(e) => open(e)}
                onDelete={(e) => {
                  setDone('')
                  setToDelete(e)
                }}
              />
            ))
          )}
        </>
      )}

      <ExpenseSheet
        open={sheet !== null}
        editing={sheet?.editing ?? null}
        today={localDay(now)}
        onClose={() => setSheet(null)}
        save={save}
        onDelete={sheet?.editing ? () => setToDelete(sheet.editing) : undefined}
      />
      <DeleteDialog expense={toDelete} onClose={() => setToDelete(null)} remove={remove} />
    </div>
  )
}

/** « Supprimer « Loyer » (90 000 FCFA) ? » — Garder / Supprimer. */
function DeleteDialog({
  expense,
  onClose,
  remove,
}: {
  expense: Expense | null
  onClose: () => void
  remove: (expense: Expense) => Promise<void>
}) {
  const titleId = useId()
  const [busy, setBusy] = useState(false)
  const [failed, setFailed] = useState(false)
  // Kept while the dialog closes, so its text does not vanish mid-animation.
  const [shown, setShown] = useState<Expense | null>(expense)
  if (expense && expense !== shown) {
    setShown(expense)
    setFailed(false)
  }
  const confirm = async () => {
    if (!expense) return
    setBusy(true)
    setFailed(false)
    try {
      await remove(expense)
    } catch {
      setFailed(true)
    } finally {
      setBusy(false)
    }
  }
  return (
    <Dialog open={expense !== null} onClose={onClose} labelledBy={titleId}>
      {shown && (
        <div className="dialog__body">
          <h2 className="dialog__title" id={titleId}>
            {`Supprimer «\u00a0${shown.label || categoryLabel(shown.category)}\u00a0» (${money(Number(shown.amount))})\u00a0?`}
          </h2>
          <p className="dialog__text">Elle sortira des comptes du mois.</p>
          {failed && (
            <p className="field__error" role="alert">
              Pas supprimée : le réseau ne répond pas. Réessayez.
            </p>
          )}
          <div className="dialog__actions">
            <Button variant="secondary" onClick={onClose} autoFocus>
              Garder
            </Button>
            <Button variant="danger" solid busy={busy} onClick={() => void confirm()}>
              Supprimer
            </Button>
          </div>
        </div>
      )}
    </Dialog>
  )
}
