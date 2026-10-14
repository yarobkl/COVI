import { useEffect, useState, type FormEvent } from 'react'
import { Button, Notice } from '../../components/ui'
import {
  createSharedCashier,
  listSharedCashiers,
  setSharedCashierActive,
  type SharedCashier,
} from '../../lib/sharedCashiers'
import { pinProblem, teamErrorMessage } from '../../lib/teamRules'

const discounts = Array.from({ length: 101 }, (_, percent) => percent)

/**
 * Employees use the ONE shared shop account, but every cashier has their OWN
 * personal PIN. No extra email, password or employee Supabase account required.
 */
export function SharedCashiersPanel({ shopId }: { shopId: string }) {
  const [cashiers, setCashiers] = useState<SharedCashier[] | null>(null)
  const [name, setName] = useState('')
  const [pin, setPin] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [discount, setDiscount] = useState(0)
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
      await createSharedCashier(shopId, name.trim(), pin, discount)
      setPin('')
      setConfirmation('')
      setName('')
      setDiscount(0)
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
    <section className="card team">
      <h3>Caissiers de cette boutique</h3>
      <p className="muted">
        Le compte de gestion est commun. Chaque employé choisit son propre code PIN pour encaisser
        et retrouver ses ventes.
      </p>
      {cashiers === null && !error && <p>Chargement des caissiers…</p>}
      {cashiers?.length === 0 && <p>Aucun caissier pour le moment.</p>}
      {cashiers && cashiers.length > 0 && (
        <ul className="team-members">
          {cashiers.map((cashier) => (
            <li key={cashier.id}>
              <span>
                <b>{cashier.display_name}</b>
                {' · '}
                {cashier.active ? 'Actif' : 'Désactivé'}
                {' · '}
                Remise maximale : {cashier.max_discount_pct} %
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
      <h3>Ajouter un caissier</h3>
      <form className="formgrid" onSubmit={(event) => void create(event)}>
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
          Remise maximale autorisée
          <select value={discount} onChange={(event) => setDiscount(Number(event.target.value))}>
            {discounts.map((value) => (
              <option key={value} value={value}>
                {value} %
              </option>
            ))}
          </select>
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
        <Button variant="primary" disabled={busy} type="submit">
          {busy ? 'Enregistrement…' : 'Créer le caissier'}
        </Button>
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
