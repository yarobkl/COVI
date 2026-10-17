import { useCallback, useEffect, useState } from 'react'
import { Button, Notice, PageHead, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import type { Tables } from '../../lib/database.types'

type Booking = Tables<'salon_booking_requests'>
type Link = Tables<'salon_booking_links'>

const states: Record<string, string> = {
  pending: 'À confirmer',
  confirmed: 'Confirmé',
  declined: 'Refusé',
  cancelled: 'Annulé',
  completed: 'Terminé',
  no_show: 'Absent',
}

/** Owner's private appointment book. Public forms need abuse protection before activation. */
export function SalonBookingsPage({ shopId }: { shopId: string }) {
  const [rows, setRows] = useState<Booking[]>([])
  const [link, setLink] = useState<Link | null>(null)
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState(false)

  const refresh = useCallback(async () => {
    const [bookings, links] = await Promise.all([
      supabase.from('salon_booking_requests').select('*').eq('shop_id', shopId)
        .order('requested_at', { ascending: true }),
      supabase.from('salon_booking_links').select('*').eq('shop_id', shopId).maybeSingle(),
    ])
    if (bookings.error || links.error) throw bookings.error ?? links.error
    setRows(bookings.data ?? [])
    setLink(links.data)
  }, [shopId])

  useEffect(() => {
    let active = true
    void Promise.all([
      supabase.from('salon_booking_requests').select('*').eq('shop_id', shopId)
        .order('requested_at', { ascending: true }),
      supabase.from('salon_booking_links').select('*').eq('shop_id', shopId).maybeSingle(),
    ]).then(([bookings, links]) => {
      if (!active) return
      setLoading(false)
      if (bookings.error || links.error) {
        setError(true); setMessage('Agenda indisponible. La migration est peut-être en attente.')
      } else {
        setRows(bookings.data ?? [])
        setLink(links.data)
      }
    })
    return () => { active = false }
  }, [shopId])

  const linkUrl = link ? `${window.location.origin}/#/reserver/${link.public_token}` : ''

  async function createLink() {
    if (busy) return
    setBusy(true)
    try {
      const { error: insertError } = await supabase
        .from('salon_booking_links').insert({ shop_id: shopId })
      if (insertError) throw insertError
      await refresh()
      setError(false); setMessage('Lien unique de votre salon créé. Les réservations publiques nécessitent encore l’activation des protections anti-abus.')
    } catch {
      setError(true); setMessage('Création du lien impossible.')
    } finally { setBusy(false) }
  }

  async function setStatus(b: Booking, status: 'confirmed' | 'declined' | 'completed') {
    if (busy) return
    setBusy(true)
    try {
      const { error: updateError } = await supabase.from('salon_booking_requests')
        .update({ status }).eq('id', b.id).eq('shop_id', shopId)
      if (updateError) throw updateError
      await refresh()
      setError(false); setMessage('Rendez-vous mis à jour.')
    } catch {
      setError(true); setMessage('Impossible de modifier ce rendez-vous.')
    } finally { setBusy(false) }
  }

  return <div className="page-stack">
    <PageHead title="Rendez-vous" sub="Les demandes sont privées à ce salon. Une demande n’est jamais automatiquement confirmée."/>
    <Sheet aria-label="Lien de réservation">
      <h2 className="section-title">Lien du salon</h2>
      {link ? <>
        <p className="muted">Ce lien identifie uniquement votre salon. Il pourra être encodé dans un QR permanent, sans inclure de données clients.</p>
        <p><a href={linkUrl} target="_blank" rel="noreferrer">Voir la page de réservation du salon</a></p>
        <Button variant="secondary" onClick={()=>void navigator.clipboard.writeText(linkUrl)}>Copier le lien</Button>
      </> : <Button variant="primary" busy={busy} onClick={()=>void createLink()}>Créer mon lien unique</Button>}
      <Notice tone="calm"><p>Le formulaire QR public n’accepte pas encore les réservations : l’anti-spam et la validation des disponibilités doivent être testés avant son ouverture.</p></Notice>
    </Sheet>
    {message && <Notice tone={error?'danger':'success'}><p>{message}</p></Notice>}
    <Sheet aria-label="Demandes de rendez-vous">
      <h2 className="section-title">Demandes reçues</h2>
      {loading ? <p>Chargement des rendez-vous…</p> : rows.length===0 ?
        <p className="muted">Aucune demande pour l’instant.</p> :
        <ul className="team-invites">{rows.map(b => <li key={b.id}>
          <div>
            <strong>{b.first_name} {b.last_name}</strong>
            <p className="muted">{new Date(b.requested_at).toLocaleString('fr-FR')} · {b.phone} · {states[b.status] ?? b.status}</p>
          </div>
          <div className="row-actions">
            {b.status==='pending' && <>
              <Button disabled={busy} onClick={()=>void setStatus(b,'confirmed')}>Confirmer</Button>
              <Button disabled={busy} onClick={()=>void setStatus(b,'declined')}>Refuser</Button>
            </>}
            {b.status==='confirmed' && <Button disabled={busy} onClick={()=>void setStatus(b,'completed')}>Terminé</Button>}
          </div>
        </li>)}</ul>}
    </Sheet>
  </div>
}
