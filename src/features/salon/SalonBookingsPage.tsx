import { useCallback, useEffect, useState, type FormEvent } from 'react'
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
  const [showForm, setShowForm] = useState(false)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState('')
  const [error, setError] = useState(false)

  const refresh = useCallback(async () => {
    const [bookings, links] = await Promise.all([
      supabase
        .from('salon_booking_requests')
        .select('*')
        .eq('shop_id', shopId)
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
      supabase
        .from('salon_booking_requests')
        .select('*')
        .eq('shop_id', shopId)
        .order('requested_at', { ascending: true }),
      supabase.from('salon_booking_links').select('*').eq('shop_id', shopId).maybeSingle(),
    ]).then(([bookings, links]) => {
      if (!active) return
      setLoading(false)
      if (bookings.error || links.error) {
        setError(true)
        setMessage('Agenda indisponible. La migration est peut-être en attente.')
      } else {
        setRows(bookings.data ?? [])
        setLink(links.data)
      }
    })
    return () => {
      active = false
    }
  }, [shopId])

  async function createManualBooking(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (busy) return
    const form = new FormData(event.currentTarget)
    const firstName = String(form.get('first_name') ?? '').trim()
    const lastName = String(form.get('last_name') ?? '').trim()
    const phone = String(form.get('phone') ?? '').trim()
    const time = String(form.get('requested_at') ?? '')
    const date = new Date(time)
    if (
      firstName.length < 1 ||
      lastName.length < 1 ||
      !/^\\+?[0-9][0-9 ()-]{5,23}$/.test(phone) ||
      !Number.isFinite(date.getTime()) ||
      date.getTime() <= Date.now()
    ) {
      setError(true)
      setMessage('Vérifiez le contact et sélectionnez une date future.')
      return
    }
    setBusy(true)
    try {
      const { error: insertError } = await supabase.from('salon_booking_requests').insert({
        shop_id: shopId,
        first_name: firstName,
        last_name: lastName,
        phone,
        requested_at: date.toISOString(),
        status: 'pending',
      })
      if (insertError) throw insertError
      await refresh()
      setShowForm(false)
      setError(false)
      setMessage('Rendez-vous enregistré comme demande. Confirmez-le pour réserver ce créneau.')
    } catch {
      setError(true)
      setMessage('Impossible de créer ce rendez-vous. Vérifiez vos droits et réessayez.')
    } finally {
      setBusy(false)
    }
  }

  async function createLink() {
    if (busy) return
    setBusy(true)
    try {
      const { error: insertError } = await supabase
        .from('salon_booking_links')
        .insert({ shop_id: shopId })
      if (insertError) throw insertError
      await refresh()
      setError(false)
      setMessage(
        'Lien unique de votre salon créé. Les réservations publiques nécessitent encore l’activation des protections anti-abus.',
      )
    } catch {
      setError(true)
      setMessage('Création du lien impossible.')
    } finally {
      setBusy(false)
    }
  }

  async function setStatus(b: Booking, status: 'confirmed' | 'declined' | 'completed') {
    if (busy) return
    setBusy(true)
    try {
      const { error: updateError } = await supabase.rpc('salon_change_booking_status', {
        p_shop: shopId,
        p_booking: b.id,
        p_status: status,
      })
      if (updateError) throw updateError
      await refresh()
      setError(false)
      setMessage('Rendez-vous mis à jour.')
    } catch (e) {
      setError(true)
      const reason = e instanceof Error ? e.message : String(e)
      setMessage(
        reason.includes('already confirmed')
          ? 'Ce créneau est déjà réservé. Proposez une autre heure au client.'
          : 'Impossible de modifier le rendez-vous. Vérifiez son état et réessayez.',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="page-stack">
      <PageHead
        title="Rendez-vous"
        sub="Les demandes sont privées à ce salon. Une demande n’est jamais automatiquement confirmée."
      />
      <Sheet aria-label="Ajouter un rendez-vous">
        <h2 className="section-title">Votre agenda au quotidien</h2>
        <p className="muted">
          Enregistrez une demande reçue par téléphone ou directement au salon, puis confirmez le créneau.
          Rien n'est considéré comme payé automatiquement.
        </p>
        <Button onClick={() => setShowForm(!showForm)}>
          {showForm ? 'Fermer le formulaire' : 'Ajouter un rendez-vous'}
        </Button>
        {showForm && (
          <form className="form-grid" onSubmit={(event) => void createManualBooking(event)}>
            <label>
              Prénom
              <input name="first_name" required maxLength={80} />
            </label>
            <label>
              Nom
              <input name="last_name" required maxLength={80} />
            </label>
            <label>
              Téléphone
              <input name="phone" type="tel" required placeholder="+242061234567" />
            </label>
            <label>
              Date et heure souhaitées
              <input name="requested_at" type="datetime-local" required />
            </label>
            <Button variant="primary" type="submit" busy={busy}>
              Enregistrer la demande
            </Button>
          </form>
        )}
      </Sheet>
      <Sheet aria-label="Lien de réservation">
        <h2 className="section-title">Lien du salon</h2>
        {link ? (
          <>
            <p className="muted">
              Ce lien identifie uniquement votre salon. Il pourra être encodé dans un QR permanent,
              sans inclure de données clients.
            </p>
            <p className="muted">
              Le lien sécurisé de ce salon est réservé, mais la page publique n’est pas encore
              activée. Ne partagez pas encore ce lien avec les clients.
            </p>
            <Button variant="secondary" disabled title="Réservation publique en préparation">
              Partage disponible après activation
            </Button>
          </>
        ) : (
          <Button variant="primary" busy={busy} onClick={() => void createLink()}>
            Créer mon lien unique
          </Button>
        )}
        <Notice tone="calm">
          <p>
            Le formulaire QR public n’accepte pas encore les réservations : l’anti-spam et la
            validation des disponibilités doivent être testés avant son ouverture.
          </p>
        </Notice>
      </Sheet>
      {message && (
        <Notice tone={error ? 'danger' : 'success'}>
          <p>{message}</p>
        </Notice>
      )}
      <Sheet aria-label="Demandes de rendez-vous">
        <h2 className="section-title">Demandes reçues</h2>
        {loading ? (
          <p>Chargement des rendez-vous…</p>
        ) : rows.length === 0 ? (
          <p className="muted">Aucune demande pour l’instant.</p>
        ) : (
          <ul className="team-invites">
            {rows.map((b) => (
              <li key={b.id}>
                <div>
                  <strong>
                    {b.first_name} {b.last_name}
                  </strong>
                  <p className="muted">
                    {new Date(b.requested_at).toLocaleString('fr-FR')} · {b.phone} ·{' '}
                    {states[b.status] ?? b.status}
                  </p>
                </div>
                <div className="row-actions">
                  {b.status === 'pending' && (
                    <>
                      <Button disabled={busy} onClick={() => void setStatus(b, 'confirmed')}>
                        Confirmer
                      </Button>
                      <Button disabled={busy} onClick={() => void setStatus(b, 'declined')}>
                        Refuser
                      </Button>
                    </>
                  )}
                  {b.status === 'confirmed' && (
                    <Button disabled={busy} onClick={() => void setStatus(b, 'completed')}>
                      Terminé
                    </Button>
                  )}
                </div>
              </li>
            ))}
          </ul>
        )}
      </Sheet>
    </div>
  )
}
