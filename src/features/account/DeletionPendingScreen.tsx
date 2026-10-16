import { useState } from 'react'
import { Button, Notice } from '../../components/ui'
import { cancelAccountDeletion, deletionDay } from '../../lib/account'

/**
 * Compte dont la suppression est programmée : plus rien d'autre n'est accessible. Le propriétaire
 * peut annuler (tout revient comme avant) ou se déconnecter.
 */
export function DeletionPendingScreen({
  purgeAfter,
  onCancelled,
  onSignOut,
}: {
  purgeAfter: string
  onCancelled: () => void
  onSignOut: () => void
}) {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const cancel = async () => {
    setBusy(true)
    setError('')
    try {
      await cancelAccountDeletion()
      onCancelled()
    } catch {
      setError('L’annulation n’a pas abouti. Vérifiez la connexion et réessayez.')
      setBusy(false)
    }
  }
  return (
    <div className="authshell">
      <main className="authcard deletion-pending" aria-labelledby="deletion-pending-title">
        <h1 className="page-title" id="deletion-pending-title">
          Suppression programmée
        </h1>
        <p>
          Votre compte et votre boutique seront effacés définitivement le{' '}
          <b>{deletionDay(purgeAfter)}</b>. D’ici là, la boutique ne reçoit plus de commandes en
          ligne.
        </p>
        <p>Vous avez changé d’avis ? Annulez : tout revient exactement comme avant.</p>
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        <div className="deletion-pending__actions">
          <Button variant="primary" busy={busy} onClick={() => void cancel()}>
            Annuler la suppression
          </Button>
          <Button variant="ghost" disabled={busy} onClick={onSignOut}>
            Se déconnecter
          </Button>
        </div>
      </main>
    </div>
  )
}
