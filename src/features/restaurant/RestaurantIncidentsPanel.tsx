import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Button, Notice, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'

type Incident = Tables<'restaurant_served_incidents'>
type Decision = 'reviewed' | 'rejected' | 'requires_refund_review'

/** Private owner-only incident queue. A review never makes any actual reimbursement. */
export function RestaurantIncidentsPanel({ shopId }: { shopId: string }) {
  const [incidents, setIncidents] = useState<Incident[]>([])
  const [decision, setDecision] = useState<Decision>('reviewed')
  const [selected, setSelected] = useState('')
  const [note, setNote] = useState('')
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')

  const reload = useCallback(async () => {
    const { data, error: fault } = await supabase
      .from('restaurant_served_incidents')
      .select('*')
      .eq('shop_id', shopId)
      .eq('state', 'open')
      .order('created_at', { ascending: true })
      .limit(50)
    if (fault) throw fault
    setIncidents(data ?? [])
    setSelected(old => (data ?? []).some(row => row.id === old) ? old : data?.[0]?.id ?? '')
  }, [shopId])
  useEffect(() => {
    let live = true
    void Promise.resolve().then(() => reload()).catch(() => {
      if (live) setError('Dossiers non disponibles. Réessayez plus tard.')
    }).finally(() => {
      if (live) setLoading(false)
    })
    return () => { live = false }
  }, [reload])
  async function review(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (busy || !selected || note.trim().length < 12) return
    setBusy(true)
    setError('')
    setMessage('')
    try {
      const { data, error: fault } = await supabase.rpc('restaurant_review_served_issue', {
        p_shop: shopId, p_ticket: selected, p_decision: decision, p_note: note.trim(),
      })
      if (fault || data !== true) throw fault ?? Error('Revue non enregistrée.')
      setNote('')
      await reload()
      setMessage('Examen enregistré. Aucun remboursement ni modification de caisse n’a été effectué.')
    } catch {
      setError('Revue non confirmée. Vérifiez le journal avant de recommencer.')
    } finally {
      setBusy(false)
    }
  }
  const current = incidents.find(i => i.id === selected)

  return (
    <Sheet aria-label="Incidents concernant les articles servis">
      <h2 className="section-title">Incidents après service</h2>
      <p className="muted">Signalements à examiner par le propriétaire. Une décision « remboursement à examiner » n’est ni un paiement, ni une annulation de vente.</p>
      {error && <Notice tone="danger"><p>{error}</p></Notice>}
      {message && <Notice tone="success"><p>{message}</p></Notice>}
      {loading ? <p>Chargement des incidents…</p> :
        incidents.length === 0 ? <p className="muted">Aucun incident à examiner.</p> :
        <>
          <p className="muted">Jusqu’aux 50 plus anciens incidents ouverts sont affichés.</p>
          <form className="form-grid" onSubmit={(e) => void review(e)}>
            <label>
              Incident
              <select value={selected} onChange={e => { setSelected(e.target.value); setNote('') }}>
                {incidents.map(i => <option key={i.id} value={i.id}>
                  {new Date(i.created_at).toLocaleString('fr-FR')} · {i.description.slice(0, 80)}
                </option>)}
              </select>
            </label>
            {current && <p>{current.description}</p>}
            <label>
              Décision
              <select value={decision} onChange={e => setDecision(e.target.value as Decision)}>
                <option value="reviewed">Incident examiné</option>
                <option value="requires_refund_review">Remboursement à examiner (non effectué)</option>
                <option value="rejected">Demande rejetée</option>
              </select>
            </label>
            <label>
              Note du propriétaire
              <textarea required minLength={12} maxLength={500} value={note}
                onChange={e => setNote(e.target.value)}
                placeholder="Décision et suites à donner ; ne pas inscrire de remboursement fictif" />
            </label>
            <Button type="submit" busy={busy} disabled={!selected || note.trim().length < 12}>
              Enregistrer la décision
            </Button>
          </form>
        </>
      }
    </Sheet>
  )
}
