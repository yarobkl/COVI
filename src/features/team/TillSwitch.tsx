import { useId, useState } from 'react'
import { Button, Dialog, Notice } from '../../components/ui'
import { useSyncState } from '../sync/useSyncState'

const HANDOFF_EXPLANATION = [
  'Vous allez vous déconnecter.',
  'Le caissier se connectera avec son propre compte COVI, puis saisira son code PIN personnel.',
  'Vos accès de responsable ne restent pas ouverts sur cet appareil.',
].join(' ')
const INVITE_EXPLANATION = [
  'Pas encore de compte caissier ?',
  'Depuis Ma boutique, rubrique Équipe, créez d’abord son invitation.',
  'Vous pouvez utiliser le même téléphone ou ordinateur.',
].join(' ')

/**
 * Hand the SAME physical device to a cashier WITHOUT sharing the owner's Supabase JWT.
 * The cashier signs in with a distinct account and unlocks their own PIN.
 *
 * IMPORTANT: a PIN-only counter overlay on the owner's authenticated browser is NOT
 * an authorization boundary. Never call open_till_session from this owner screen.
 */
export function TillSwitch({ onHandoff }: { onHandoff: () => Promise<void> }) {
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const titleId = useId()
  const { pending } = useSyncState()

  const handoff = async () => {
    if (pending > 0 || busy) return
    setBusy(true)
    setError('')
    try {
      await onHandoff()
      setOpen(false)
    } catch {
      setError('La déconnexion a échoué. Réessayez avant de confier l’appareil au caissier.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="till-switch">
      <p className="till-switch__who">
        Caissier : <b>Vous (responsable)</b>
      </p>
      <Button variant="secondary" onClick={() => setOpen(true)}>
        Passer la caisse
      </Button>
      <Dialog open={open} onClose={() => !busy && setOpen(false)} labelledBy={titleId} sheet>
        <div className="dialog__body till-switch__dialog">
          <h2 className="dialog__title" id={titleId}>
            Passer la caisse à un employé
          </h2>
          <p>{HANDOFF_EXPLANATION}</p>
          <p className="muted">{INVITE_EXPLANATION}</p>
          {pending > 0 && (
            <Notice tone="danger">
              <p>{pending} vente(s) en attente de synchronisation. Ne changez pas de compte.</p>
            </Notice>
          )}
          {error && (
            <Notice tone="danger">
              <p>{error}</p>
            </Notice>
          )}
          <div className="dialog__actions">
            <Button variant="secondary" disabled={busy} onClick={() => setOpen(false)}>
              Annuler
            </Button>
            <Button
              variant="primary"
              busy={busy}
              disabled={pending > 0 || busy}
              onClick={() => void handoff()}
            >
              Déconnecter le responsable
            </Button>
          </div>
        </div>
      </Dialog>
    </div>
  )
}
