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
  const [selectedId, setSelectedId] = useState<string | null>(null)

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
    void supabase
      .from('restaurant_tables')
      .select('*')
      .eq('shop_id', shopId)
      .order('label')
      .then(({ data, error }) => {
        if (!alive) return
        setLoading(false)
        if (error) {
          setIsError(true)
          setMessage(
            'Plan de salle indisponible. La mise à jour de la base est peut-être en attente.',
          )
        } else setRows(data ?? [])
      })
    return () => {
      alive = false
    }
  }, [shopId])

  const selected = rows.find((row) => row.id === selectedId) ?? rows[0] ?? null

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
          La configuration des tables est disponible. Les statuts « occupée », « en préparation » et
          « payée » seront reliés aux commandes et à la caisse dans l'étape suivante. Aucun état
          d'occupation n'est inventé.
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
            Touchez une table pour la sélectionner. Il s'agit des emplacements configurés, pas
            encore des états d'occupation en temps réel.
          </p>
          <div className="floor-plan" role="group" aria-label="Disposition du restaurant">
            {rows.map((table) => (
              <button
                type="button"
                key={table.id}
                aria-pressed={selected?.id === table.id}
                className="floor-plan__table"
                style={{
                  left: `${Math.min(80, table.pos_x)}%`,
                  top: `${Math.min(80, table.pos_y)}%`,
                }}
                onClick={() => setSelectedId(table.id)}
              >
                Table {table.label}
                <small>{table.capacity} places</small>
              </button>
            ))}
          </div>
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
                <span className="muted">Capacité configurée</span>
              </li>
            ))}
          </ul>
        )}
      </Sheet>
    </div>
  )
}
