import { useEffect, useState, type FormEvent } from 'react'
import { Button, Notice } from '../../components/ui'
import {
  createSharedCashier,
  listSharedCashiers,
  setSharedCashierActive,
  type SharedCashier,
} from '../../lib/sharedCashiers'
import { pinProblem, teamErrorMessage } from '../../lib/teamRules'

/**
 * Employees use the ONE shared shop account, but every cashier has their OWN
 * personal PIN. No extra email, password or employee Supabase account required.
 */
export function SharedCashiersPanel({ shopId }: { shopId: string }) {
  const [cashiers, setCashiers] = useState<SharedCashier[] | null>(null)
  const [name, setName] = useState('')
  const [pin, setPin] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')

  const reload = async () => setCashiers(await listSharedCashiers(shopId))

  useEffect(() => {
    let active = true
    void listSharedCashiers(shopId).then(
      (rows) => {
        if (active) setCashiers(rows)
      },
      (err) => {
        if (active) setError(teamErrorMessage(err))
      },
    )
    return () => {
      active = false
    }
  }, [shopId])

  const create = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setError('')
    setMessage('')
    if (!name.trim()) return setError('Indiquez le prénom du caissier.')
    const invalid = pinProblem(pin)
    if (invalid) return setError(invalid)
    if (pin !== confirmation) return setError('Les deux codes PIN doivent être identiques.')
    setBusy(true)
    try {
      await createSharedCashier(shopId, name.trim(), pin, 0)
      setPin('')
      setConfirmation('')
      setName('')
      await reload()
      setMessage('Caissier créé. Il peut maintenant ouvrir sa caisse avec son PIN.')
    } catch (err) {
      setError(teamErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  const changeActive = async (cashier: SharedCashier) => {
    setBusy(true)
    setError('')
    try {
      await setSharedCashierActive(cashier.id, !cashier.active)
      await reload()
    } catch (err) {
      setError(teamErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="sheet team" aria-labelledby="shared-cashiers-title">
      <h2 className="section-title" id="shared-cashiers-title">
        Caissiers (code PIN)
      </h2>
      <p className="muted">
        Le compte de gestion est commun. Chaque employé choisit son propre code PIN pour encaisser
        et retrouver ses ventes.
      </p>
      {cashiers === null && !error && <p>Chargement des caissiers…</p>}
      {cashiers?.length === 0 && <p>Aucun caissier pour le moment.</p>}
      {cashiers && cashiers.length > 0 && (
        <ul className="team-invites" aria-label="Caissiers">
          {cashiers.map((cashier) => (
            <li key={cashier.id}>
              <span>
                <b className="team-member__name">{cashier.display_name}</b>{' '}
                <span className="muted">· {cashier.active ? 'actif' : 'désactivé'}</span>
              </span>
              <Button
                variant="secondary"
                disabled={busy}
                onClick={() => void changeActive(cashier)}
              >
                {cashier.active ? 'Désactiver' : 'Réactiver'}
              </Button>
            </li>
          ))}
        </ul>
      )}
      <form className="form-grid" onSubmit={(event) => void create(event)}>
        <h3 className="form-grid__title">Ajouter un caissier</h3>
        <label>
          Prénom du caissier
          <input
            value={name}
            onChange={(event) => setName(event.target.value)}
            maxLength={60}
            required
            autoComplete="off"
          />
        </label>
        <label>
          Code PIN personnel (4 à 6 chiffres)
          <input
            value={pin}
            onChange={(event) => setPin(event.target.value.replace(/\D/g, '').slice(0, 6))}
            type="password"
            inputMode="numeric"
            autoComplete="new-password"
            minLength={4}
            maxLength={6}
            required
          />
        </label>
        <label>
          Confirmer le code PIN
          <input
            value={confirmation}
            onChange={(event) => setConfirmation(event.target.value.replace(/\D/g, '').slice(0, 6))}
            type="password"
            inputMode="numeric"
            autoComplete="new-password"
            minLength={4}
            maxLength={6}
            required
          />
        </label>
        <div className="form-grid__actions">
          <Button variant="primary" busy={busy} busyLabel="Enregistrement…" type="submit">
            Créer le caissier
          </Button>
        </div>
      </form>
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      {message && (
        <Notice tone="success">
          <p>{message}</p>
        </Notice>
      )}
    </section>
  )
}
