import { useState } from 'react'
import { Button, Notice, PageHead, Sheet } from '../../components/ui'
import { enterCounterMode } from '../../lib/counterMode'
import { listShopMembers, ownerPinStatus, teamErrorMessage } from '../../lib/team'
import { listSharedCashiers } from '../../lib/sharedCashiers'
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
      const [owner, members, profiles] = await Promise.all([
        ownerPinStatus(shopId),
        listShopMembers(shopId),
        listSharedCashiers(shopId),
      ])
      if (
        !profiles.some((profile) => profile.active) &&
        !members.some((m) => m.active && m.pin_set && !m.pin_must_change)
      ) {
        setError(
          'Aucun caissier prêt. Ouvrez Ma boutique → Équipe et créez un caissier avec son PIN.',
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
      <Sheet>
        <OwnerPinSetup
          shopId={shopId}
          onDone={() => {
            setSetup(false)
            enterCounterMode(shopId)
          }}
          onCancel={() => setSetup(false)}
        />
      </Sheet>
    )
  }

  return (
    <div className="page-stack">
      <PageHead
        title="Vendre"
        sub="La gestion reste connectée ; chaque vente porte le nom du caissier."
      />
      <Sheet className="till-switch" aria-labelledby="till-switch-title">
        <h2 className="section-title" id="till-switch-title">
          Passer en caisse
        </h2>
        <p>Chaque caissier choisit son prénom et saisit son propre PIN avant de vendre.</p>
        {pending > 0 && (
          <Notice tone="danger">
            <p>{pending} vente(s) en attente. Attendez leur synchronisation.</p>
          </Notice>
        )}
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        <Button
          variant="sale"
          size="lg"
          busy={busy}
          disabled={busy || pending > 0}
          onClick={() => void openCounter()}
        >
          Choisir un caissier
        </Button>
      </Sheet>
    </div>
  )
}
