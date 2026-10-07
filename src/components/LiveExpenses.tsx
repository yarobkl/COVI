import { FormEvent, useEffect, useMemo, useState } from 'react'
import { Plus } from 'lucide-react'
import { createExpense, deleteExpense, Expense, listExpenses, updateExpense } from '../lib/operations'

const categories = ['Loyer','Électricité','Eau','Internet','Téléphone','Salaire','Prime','Transport','Livraison','Carburant','Manutention','Emballage','Sacs','Cintres','Nettoyage','Réparations','Fournitures','Publicité Facebook / Instagram / TikTok','Influenceurs','Frais bancaires','Frais Mobile Money','Taxes / frais administratifs','Autre']
const today = () => new Date().toISOString().slice(0, 10)
const money = (n: number) => new Intl.NumberFormat('fr-FR').format(n) + ' FCFA'
type FormValues = { category: string; label: string; amount: number; expense_date: string; recurring: boolean }

export function LiveExpenses({ shopId }: { shopId: string }) {
  const [rows, setRows] = useState<Expense[]>([])
  const [show, setShow] = useState(false)
  const [editing, setEditing] = useState<Expense | null>(null)
  const [period, setPeriod] = useState<'month' | 'all'>('all')
  const [msg, setMsg] = useState('')
  const [busy, setBusy] = useState(false)
  const load = () => listExpenses(shopId).then(setRows).catch(() => setMsg('Impossible de charger les charges. Vérifiez votre connexion puis réessayez.'))
  useEffect(() => { void load() }, [shopId])
  const visible = useMemo(() => period === 'all' ? rows : rows.filter(x => x.expense_date.slice(0, 7) === today().slice(0, 7)), [rows, period])
  const total = visible.reduce((n, x) => n + Number(x.amount), 0)
  async function save(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    const f = new FormData(e.currentTarget)
    const values: FormValues = { category: String(f.get('category')), label: String(f.get('label') || '').trim(), amount: Number(f.get('amount')), expense_date: String(f.get('date')), recurring: f.get('recurring') === 'on' }
    if (!Number.isFinite(values.amount) || values.amount <= 0) { setMsg('Le montant doit être supérieur à zéro.'); return }
    setBusy(true); setMsg('')
    try {
      if (editing) await updateExpense(shopId, editing.id, values)
      else await createExpense(shopId, values)
      setShow(false); setEditing(null); setMsg(editing ? 'Charge modifiée.' : 'Charge enregistrée.'); await load()
    } catch { setMsg('Impossible d’enregistrer cette charge. Vérifiez les informations et votre connexion.') }
    finally { setBusy(false) }
  }
  function startEdit(row: Expense) { setEditing(row); setShow(true); setMsg('') }
  async function remove(row: Expense) {
    if (!window.confirm(`Supprimer la charge « ${row.label || row.category} » de ${money(Number(row.amount))} ?`)) return
    try { await deleteExpense(shopId, row.id); setMsg('Charge supprimée.'); await load() }
    catch { setMsg('Impossible de supprimer cette charge. Réessayez.') }
  }
  return <div>
    <div className="hello"><div><h1>Charges de la boutique</h1><span>Dépenses réelles et charges de simulation marquées TEST, sans doubler les arrivages.</span></div><button onClick={() => { setEditing(null); setShow(!show); setMsg('') }}><Plus />Ajouter une charge</button></div>
    <div className="summary3"><div className="kpi"><span>Charges sur la période</span><b>{money(total)}</b><small>{period === 'month' ? 'Ce mois-ci' : 'Tout l’historique, y compris les lignes TEST'}</small></div><div className="kpi"><span>Charges récurrentes</span><b>{money(visible.filter(x => x.recurring).reduce((n, x) => n + Number(x.amount), 0))}</b><small>Identifiées sur la période</small></div><div className="kpi"><span>Écritures</span><b>{visible.length}</b><small>Charges enregistrées</small></div></div>
    <section className="card expense-toolbar"><label>Période<select value={period} onChange={e => setPeriod(e.target.value as 'month' | 'all')}><option value="month">Ce mois-ci</option><option value="all">Tout l’historique</option></select></label></section>
    {show && <form className="card formgrid" onSubmit={save}><div className="span2"><h2>{editing ? 'Modifier la charge' : 'Ajouter une charge'}</h2></div><label>Catégorie<select name="category" defaultValue={editing?.category || 'Loyer'}>{categories.map(x => <option key={x}>{x}</option>)}</select></label><label>Libellé<input name="label" defaultValue={editing?.label || ''} /></label><label>Montant<input name="amount" type="number" min="1" step="1" required defaultValue={editing?.amount} /></label><label>Date<input name="date" type="date" required defaultValue={editing?.expense_date || today()} /></label><label className="span2"><span><input name="recurring" type="checkbox" defaultChecked={editing?.recurring || false} /> Charge récurrente</span></label><button className="primary span2" disabled={busy}>{busy ? 'Enregistrement…' : editing ? 'Enregistrer les modifications' : 'Enregistrer la charge'}</button>{editing && <button className="outline span2" type="button" onClick={() => { setEditing(null); setShow(false) }}>Annuler</button>}</form>}
    {msg && <p className="successmsg">{msg}</p>}
    <section className="card">{visible.length === 0 ? <p>Aucune charge sur cette période.</p> : visible.map(x => <div className="expense" key={x.id}><div className="grow"><b>{x.label || x.category} {x.is_test&&<em className="test-tag">TEST</em>}</b><span>{x.category} · {x.expense_date}{x.recurring ? ' · Récurrente' : ''}</span></div><b>- {money(Number(x.amount))}</b><button className="outline" onClick={() => startEdit(x)}>Modifier</button><button className="outline" onClick={() => void remove(x)}>Supprimer</button></div>)}</section>
  </div>
}
