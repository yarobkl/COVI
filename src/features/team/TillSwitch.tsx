import { useState } from 'react'
import { Button, Notice } from '../../components/ui'
import { enterCounterMode } from '../../lib/counterMode'
import { listShopMembers, ownerPinStatus, teamErrorMessage } from '../../lib/team'
import { OwnerPinSetup } from './OwnerPinScreens'
import { useSyncState } from '../sync/useSyncState'

/**
 * The shop management account is shared by design. Selecting a cashier does NOT
 * sign out: the existing SQL open_till_session verifies that cashier's own PIN
 * and attributes each sale to their personal user id and discount ceiling.
 *
 * WARNING: the shared management account itself is privileged. The PIN controls
 * sale attribution, not protection of management credentials from their users.
 */
export function TillSwitch({ shopId }: { shopId: string }) {
  const [busy, setBusy] = useState(false)
  const [setup, setSetup] = useState(false)
  const [error, setError] = useState('')
  const { pending } = useSyncState()

  const openCounter = async () => {
    if (busy || pending > 0) return
    setBusy(true)
    setError('')
    try {
      const [owner, members] = await Promise.all([
        ownerPinStatus(shopId),
        listShopMembers(shopId),
      ])
      if (!members.some((member) => member.active && member.pin_set && !member.pin_must_change)) {
        setError(
          'Aucun caissier prêt. Invitez un employé dans Ma boutique → Équipe et demandez-lui de créer son PIN personnel.',
        )
        return
      }
      if (!owner.pin_set) {
        setSetup(true)
        return
      }
      enterCounterMode(shopId)
    } catch (err) {
      setError(teamErrorMessage(err))
    } finally {
      setBusy(false)
    }
  }

  if (setup) {
    return (
      <section className="card">
        <OwnerPinSetup
          shopId={shopId}
          onDone={() => {
            setSetup(false)
            enterCounterMode(shopId)
          }}
          onCancel={() => setSetup(false)}
        />
      </section>
    )
  }

  return (
    <section className="card till-switch">
      <h2>Passer en caisse</h2>
      <p>
        Le compte de gestion de la boutique reste connecté. Chaque caissier choisit
        son prénom et saisit son propre code PIN avant de vendre.
      </p>
      <p className="muted">
        Les ventes sont enregistrées au nom du caissier sélectionné, avec sa limite
        de remise. Vous pouvez changer de caissier sans vous déconnecter.
      </p>
      {pending > 0 && (
        <Notice tone="danger">
          <p>
            {pending} vente(s) en attente de synchronisation. Attendez leur envoi
            avant de changer de caisse.
          </p>
        </Notice>
      )}
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      <Button
        variant="primary"
        busy={busy}
        disabled={busy || pending > 0}
        onClick={() => void openCounter()}
      >
        Choisir un caissier
      </Button>
    </section>
  )
}
