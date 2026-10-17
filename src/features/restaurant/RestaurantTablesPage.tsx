import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Button, PageHead, Sheet, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'

type Table = Tables<'restaurant_tables'>

/** Owner's room plan; availability will come from actual sessions in the next increment. */
export function RestaurantTablesPage({ shopId }: { shopId: string }) {
  const [rows, setRows] = useState<Table[]>([])
  const [busy, setBusy] = useState(false)
  const [showForm, setShowForm] = useState(false)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState('')
  const [isError, setIsError] = useState(false)

  const reload = useCallback(async () => {
    const { data, error } = await supabase
      .from('restaurant_tables')
      .select('*')
      .eq('shop_id', shopId)
      .order('label')
    if (error) throw error
    setRows(data ?? [])
  }, [shopId])

  useEffect(() => {
    let alive = true
    void supabase.from('restaurant_tables').select('*').eq('shop_id', shopId).order('label')
      .then(({ data, error }) => {
        if (!alive) return
        setLoading(false)
        if (error) { setIsError(true); setMessage('Plan de salle indisponible. La mise à jour de la base est peut-être en attente.') }
        else setRows(data ?? [])
      })
    return () => { alive = false }
  }, [shopId])

  async function add(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (busy) return
    const form = new FormData(e.currentTarget)
    const label = String(form.get('label') ?? '').trim()
    const zone = String(form.get('zone') ?? '').trim()
    const capacity = Number(form.get('capacity'))
    if (!label || !zone || !Number.isInteger(capacity) || capacity < 1 || capacity > 50) {
      setIsError(true); setMessage('Indiquez la table, sa salle et une capacité entre 1 et 50.')
      return
    }
    setBusy(true)
    try {
      const { error } = await supabase.from('restaurant_tables')
        .insert({ shop_id: shopId, label, zone, capacity })
      if (error) throw error
      await reload()
      setShowForm(false)
      setIsError(false)
      setMessage('Table ajoutée à votre salle.')
    } catch {
      setIsError(true); setMessage('Enregistrement impossible. Vérifiez le numéro de table et réessayez.')
    } finally { setBusy(false) }
  }

  return <div className="page-stack">
    <PageHead title="Plan de salle" sub="Vos tables et leur capacité, sans confusion entre restaurants."
      action={<Button onClick={() => setShowForm(!showForm)}>{showForm ? 'Fermer' : 'Ajouter une table'}</Button>} />
    <Notice tone="calm">
      <p>La configuration des tables est disponible. Les statuts « occupée », « en préparation » et « payée » seront reliés aux commandes et à la caisse dans l'étape suivante. Aucun état d'occupation n'est inventé.</p>
    </Notice>
    {showForm && <Sheet>
      <form className="form-grid" onSubmit={e => void add(e)}>
        <label>Numéro ou nom<input name="label" placeholder="Ex. 04" maxLength={40} required /></label>
        <label>Zone<input name="zone" defaultValue="Salle principale" maxLength={80} required /></label>
        <label>Nombre de places<input name="capacity" type="number" min={1} max={50} defaultValue={4} required /></label>
        <Button variant="primary" type="submit" busy={busy}>Enregistrer la table</Button>
      </form>
    </Sheet>}
    {message && <Notice tone={isError ? 'danger' : 'success'}><p>{message}</p></Notice>}
    <Sheet aria-label="Tables du restaurant">
      {loading ? <p>Chargement des tables…</p> : rows.length === 0 ?
        <p className="muted">Aucune table configurée.</p> :
        <ul className="team-invites">{rows.map(table =>
          <li key={table.id}><div><strong>Table {table.label}</strong><p className="muted">{table.zone} · {table.capacity} places</p></div><span className="muted">Capacité configurée</span></li>)}</ul>}
    </Sheet>
  </div>
}
