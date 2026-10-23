import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { Button, PageHead, Sheet, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { restaurantQrLink } from '../../lib/restaurantQr'
import qrcode from '../../vendor/qrcode-generator.mjs'
import type { Tables } from '../../lib/database.types'

type Table = Tables<'restaurant_tables'>
type Session = Tables<'restaurant_table_sessions'>

/** Owner's room plan: status is read from active table sessions, never inferred from appearance. */
export function RestaurantTablesPage({ shopId }: { shopId: string }) {
  const [rows, setRows] = useState<Table[]>([])
  const [sessions, setSessions] = useState<Session[]>([])
  const [statusError, setStatusError] = useState(false)
  const [syncedAt, setSyncedAt] = useState('')
  const [busy, setBusy] = useState(false)
  const [showForm, setShowForm] = useState(false)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState('')
  const [isError, setIsError] = useState(false)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [planView, setPlanView] = useState<'grid' | 'physical'>('grid')

  const reload = useCallback(async () => {
    const [tables, active] = await Promise.all([
      supabase.from('restaurant_tables').select('*').eq('shop_id', shopId).order('label'),
      supabase
        .from('restaurant_table_sessions')
        .select('*')
        .eq('shop_id', shopId)
        .in('status', ['collecting', 'submitted'])
        .limit(1000),
    ])
    if (tables.error || active.error) throw new Error('Impossible de synchroniser la salle.')
    if ((tables.data?.length ?? 0) >= 1000 || (active.data?.length ?? 0) >= 1000)
      throw new Error('Le plan ne peut pas garantir la liste complète des tables.')
    setRows(tables.data ?? [])
    setSessions(active.data ?? [])
    setSyncedAt(new Date().toLocaleTimeString('fr-FR'))
    setStatusError(false)
  }, [shopId])

  useEffect(() => {
    let mounted = true
    const sync = async () => {
      try {
        await reload()
        if (mounted) {
          setIsError(false)
          setMessage('')
        }
      } catch {
        if (mounted) {
          setStatusError(true)
          setIsError(true)
          setMessage(
            'État de la salle indisponible : aucune table ne sera déclarée libre sans vérification.',
          )
        }
      } finally {
        if (mounted) setLoading(false)
      }
    }
    void sync()
    const interval = window.setInterval(() => {
      void sync()
    }, 10000)
    const channel = supabase
      .channel(`restaurant-room-${shopId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'restaurant_table_sessions',
          filter: `shop_id=eq.${shopId}`,
        },
        () => {
          void sync()
        },
      )
      .subscribe()
    return () => {
      mounted = false
      window.clearInterval(interval)
      void supabase.removeChannel(channel)
    }
  }, [reload, shopId])

  const selected = rows.find((row) => row.id === selectedId) ?? rows[0] ?? null
  const qrLink = selected?.qr_token
    ? restaurantQrLink(window.location.origin, selected.qr_token)
    : ''
  const svgQr = (() => {
    if (!qrLink) return ''
    try {
      const code = qrcode(0, 'M')
      code.addData(qrLink)
      code.make()
      return code.createSvgTag({ cellSize: 7, margin: 5 })
    } catch {
      return ''
    }
  })()
  const qrImage = svgQr ? `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svgQr)}` : ''

  function downloadQr() {
    if (!svgQr || !selected) return
    const objectUrl = URL.createObjectURL(new Blob([svgQr], { type: 'image/svg+xml' }))
    const a = document.createElement('a')
    a.href = objectUrl
    a.download = `COVI-table-${selected.label.replace(/[^a-z0-9-]/gi, '_')}.svg`
    a.click()
    window.setTimeout(() => URL.revokeObjectURL(objectUrl), 1000)
  }

  async function shareQr() {
    if (!qrLink) return
    if (navigator.share) {
      try {
        await navigator.share({ title: `Table ${selected?.label} — COVI`, url: qrLink })
      } catch {
        /* Le propriétaire a annulé le partage. */
      }
      return
    }
    await copyQrLink()
  }

  async function copyQrLink() {
    if (!qrLink) return
    try {
      await navigator.clipboard.writeText(qrLink)
      setMessage('Lien client copié.')
      setIsError(false)
    } catch {
      setMessage('Copie impossible : sélectionnez le lien ci-dessous.')
      setIsError(true)
    }
  }

  async function savePlace(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (busy || !selected) return
    const form = new FormData(e.currentTarget)
    const pos_x = Number(form.get('pos_x'))
    const pos_y = Number(form.get('pos_y'))
    if (
      !Number.isInteger(pos_x) ||
      !Number.isInteger(pos_y) ||
      pos_x < 0 ||
      pos_x > 80 ||
      pos_y < 0 ||
      pos_y > 80
    ) {
      setIsError(true)
      setMessage('Choisissez deux positions comprises entre 0 et 80.')
      return
    }
    setBusy(true)
    try {
      const { error } = await supabase
        .from('restaurant_tables')
        .update({ pos_x, pos_y })
        .eq('id', selected.id)
        .eq('shop_id', shopId)
      if (error) throw error
      await reload()
      setMessage('Emplacement enregistré.')
      setIsError(false)
    } catch {
      setIsError(true)
      setMessage('Impossible de déplacer cette table.')
    } finally {
      setBusy(false)
    }
  }

  async function add(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    if (busy) return
    const form = new FormData(e.currentTarget)
    const label = String(form.get('label') ?? '').trim()
    const zone = String(form.get('zone') ?? '').trim()
    const capacity = Number(form.get('capacity'))
    if (!label || !zone || !Number.isInteger(capacity) || capacity < 1 || capacity > 50) {
      setIsError(true)
      setMessage('Indiquez la table, sa salle et une capacité entre 1 et 50.')
      return
    }
    setBusy(true)
    try {
      const { error } = await supabase.from('restaurant_tables').insert({
        shop_id: shopId,
        label,
        zone,
        capacity,
        pos_x: 6 + (rows.length % 4) * 22,
        pos_y: 6 + (Math.floor(rows.length / 4) % 3) * 28,
      })
      if (error) throw error
      await reload()
      setShowForm(false)
      setIsError(false)
      setMessage('Table ajoutée à votre salle.')
    } catch {
      setIsError(true)
      setMessage('Enregistrement impossible. Vérifiez le numéro de table et réessayez.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="page-stack">
      <PageHead
        title="Plan de salle"
        sub="Vos tables et leur capacité, sans confusion entre restaurants."
        action={
          <Button onClick={() => setShowForm(!showForm)}>
            {showForm ? 'Fermer' : 'Ajouter une table'}
          </Button>
        }
      />
      <Notice tone="calm">
        <p>
          La disponibilité dépend des sessions et de la caisse, jamais d’un clic sur le plan.
          Actualisation automatique toutes les 10 secondes. Dernière vérification :{' '}
          {syncedAt || 'en attente'}. Si le réseau échoue, les états sont indiqués comme inconnus.
        </p>
      </Notice>
      {showForm && (
        <Sheet>
          <form className="form-grid" onSubmit={(e) => void add(e)}>
            <label>
              Numéro ou nom
              <input name="label" placeholder="Ex. 04" maxLength={40} required />
            </label>
            <label>
              Zone
              <input name="zone" defaultValue="Salle principale" maxLength={80} required />
            </label>
            <label>
              Nombre de places
              <input name="capacity" type="number" min={1} max={50} defaultValue={4} required />
            </label>
            <Button variant="primary" type="submit" busy={busy}>
              Enregistrer la table
            </Button>
          </form>
        </Sheet>
      )}
      {message && (
        <Notice tone={isError ? 'danger' : 'success'}>
          <p>{message}</p>
        </Notice>
      )}
      {rows.length > 0 && (
        <Sheet aria-label="Plan visuel de la salle">
          <h2 className="section-title">Disposition de vos tables</h2>
          <p className="muted">
            Touchez une table pour la sélectionner. Les occupations proviennent des sessions
            enregistrées, pas de la capacité ni du nombre de personnes réellement présentes.
          </p>
          <div className="row-actions" role="group" aria-label="Mode de présentation des tables">
            <Button
              variant={planView === 'grid' ? 'primary' : 'secondary'}
              aria-pressed={planView === 'grid'}
              onClick={() => setPlanView('grid')}
            >
              Vue lisible
            </Button>
            <Button
              variant={planView === 'physical' ? 'primary' : 'secondary'}
              aria-pressed={planView === 'physical'}
              onClick={() => setPlanView('physical')}
            >
              Plan physique
            </Button>
          </div>
          <div
            className={`floor-plan floor-plan--${planView}`}
            role="group"
            aria-label="Disposition du restaurant"
          >
            {rows.map((table) => {
              const session = sessions.find((x) => x.table_id === table.id)
              const state = statusError
                ? 'État inconnu'
                : session?.status === 'collecting'
                  ? 'Choix en cours'
                  : session?.status === 'submitted'
                    ? 'Occupée'
                    : 'Libre'
              return (
                <button
                  type="button"
                  key={table.id}
                  aria-label={`Table ${table.label}, ${state}, ${table.capacity} places`}
                  aria-pressed={selected?.id === table.id}
                  className={`floor-plan__table${session || statusError ? ' floor-plan__table--occupied' : ''}`}
                  style={
                    planView === 'physical'
                      ? {
                          left: `${Math.min(80, table.pos_x)}%`,
                          top: `${Math.min(80, table.pos_y)}%`,
                        }
                      : undefined
                  }
                  onClick={() => setSelectedId(table.id)}
                >
                  Table {table.label}
                  <small>{table.capacity} places</small>
                  <small>{state}</small>
                </button>
              )
            })}
          </div>
          {selected && (
            <div className="floor-plan__qr-panel">
              <h3 className="section-title">QR client · Table {selected.label}</h3>
              <p className="muted">
                Le lien est unique et permanent pour cette table. La lecture de la carte nécessite
                l’activation de la passerelle publique Restaurant.
              </p>
              {qrImage ? (
                <>
                  <img
                    className="floor-plan__qr-image"
                    src={qrImage}
                    alt={`QR code de la table ${selected.label}`}
                    width={220}
                    height={220}
                  />
                  <label>
                    Lien client
                    <input
                      aria-label="Lien client de la table"
                      readOnly
                      value={qrLink}
                      onFocus={(e) => e.target.select()}
                    />
                  </label>
                  <div className="row-actions">
                    <Button onClick={() => void copyQrLink()}>Copier le lien</Button>
                    <Button onClick={() => void shareQr()}>Partager</Button>
                    <Button onClick={downloadQr}>Télécharger le QR</Button>
                    <Button onClick={() => window.print()}>Imprimer</Button>
                  </div>
                </>
              ) : (
                <Notice tone="danger">
                  <p>QR indisponible pour cette table : vérifiez son identifiant.</p>
                </Notice>
              )}
            </div>
          )}
          {selected && (
            <form key={selected.id} className="form-grid" onSubmit={(e) => void savePlace(e)}>
              <h3 className="section-title">Position de la table {selected.label}</h3>
              <label>
                Horizontal (%)
                <input
                  name="pos_x"
                  type="number"
                  defaultValue={selected.pos_x}
                  min={0}
                  max={80}
                  required
                />
              </label>
              <label>
                Vertical (%)
                <input
                  name="pos_y"
                  type="number"
                  defaultValue={selected.pos_y}
                  min={0}
                  max={80}
                  required
                />
              </label>
              <Button type="submit" busy={busy}>
                Déplacer la table
              </Button>
            </form>
          )}
        </Sheet>
      )}
      <Sheet aria-label="Tables du restaurant">
        {loading ? (
          <p>Chargement des tables…</p>
        ) : rows.length === 0 ? (
          <p className="muted">Aucune table configurée.</p>
        ) : (
          <ul className="team-invites">
            {rows.map((table) => (
              <li key={table.id}>
                <div>
                  <strong>Table {table.label}</strong>
                  <p className="muted">
                    {table.zone} · {table.capacity} places
                  </p>
                </div>
                <span className="muted">
                  {statusError
                    ? 'État inconnu'
                    : sessions.some((x) => x.table_id === table.id)
                      ? 'Occupée'
                      : 'Libre'}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Sheet>
    </div>
  )
}
