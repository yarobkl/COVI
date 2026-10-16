import { useEffect, useId, useState } from 'react'
import { Button, Dialog, Notice, Sheet } from '../../components/ui'
import { deletionDay, requestAccountDeletion } from '../../lib/account'
import { ownerPinStatus } from '../../lib/team'

/**
 * « Supprimer mon compte » (Ma boutique). La suppression est programmée dans 30 jours : d'ici là
 * la boutique est fermée aux commandes en ligne et le propriétaire peut tout annuler.
 */
export function AccountDeletionPanel({
  shopId,
  shopName,
  onScheduled,
}: {
  shopId: string
  shopName: string
  /** Après la demande : l'application affiche l'écran « suppression programmée ». */
  onScheduled: () => void
}) {
  const titleId = useId()
  const [open, setOpen] = useState(false)
  // null : pas encore su si la boutique a un code du responsable (bouton bloqué d'ici là).
  const [needsPin, setNeedsPin] = useState<boolean | null>(null)
  const [confirm, setConfirm] = useState('')
  const [pin, setPin] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  // Jour de l'effacement si l'on confirme maintenant (calculé à l'ouverture de la boîte).
  const [purgeDay, setPurgeDay] = useState('')

  useEffect(() => {
    if (!open) return
    ownerPinStatus(shopId).then(
      (s) => setNeedsPin(s.pin_set),
      () => setNeedsPin(true),
    )
  }, [open, shopId])

  const ready =
    confirm.trim().toUpperCase() === 'SUPPRIMER' &&
    needsPin !== null &&
    (!needsPin || /^\d{4,6}$/.test(pin))

  const submit = async () => {
    setBusy(true)
    setError('')
    try {
      const result = await requestAccountDeletion(confirm, pin)
      if (result.status === 'ok') {
        setOpen(false)
        onScheduled()
        return
      }
      setError(
        result.status === 'invalid'
          ? 'Code du responsable incorrect.' +
              (result.attemptsLeft ? ` Encore ${result.attemptsLeft} essai(s).` : '')
          : result.status === 'locked'
            ? 'Trop d’essais : le code est bloqué 15 minutes.'
            : 'Tapez le mot SUPPRIMER pour confirmer.',
      )
    } catch {
      setError('La demande n’a pas abouti. Vérifiez la connexion et réessayez.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <Sheet className="account-deletion" aria-labelledby={`${titleId}-panel`}>
      <h2 className="section-title" id={`${titleId}-panel`}>
        Supprimer mon compte
      </h2>
      <p>
        Votre compte et la boutique <b>{shopName}</b> seront effacés : ventes, stock, arrivages,
        charges, commandes, caissiers et photos. Vous avez 30 jours pour changer d’avis.{' '}
        <a href="#/confidentialite">Politique de confidentialité</a>
      </p>
      <div>
        <Button
          variant="danger"
          onClick={() => {
            setPurgeDay(deletionDay(new Date(Date.now() + 30 * 86400_000).toISOString()))
            setOpen(true)
          }}
        >
          Supprimer mon compte…
        </Button>
      </div>

      <Dialog open={open} onClose={() => !busy && setOpen(false)} labelledBy={titleId}>
        <div className="dialog__body account-deletion__dialog">
          <h2 className="dialog__title" id={titleId}>
            Supprimer le compte et la boutique ?
          </h2>
          <ul className="account-deletion__list">
            <li>Tout de suite : la boutique ne reçoit plus de commandes en ligne.</li>
            <li>
              Jusqu’au <b>{purgeDay}</b> : vous pouvez tout annuler en vous reconnectant.
            </li>
            <li>
              Le {purgeDay} : le compte, la boutique et toutes ses données sont effacés
              définitivement.
            </li>
          </ul>
          <label className="field">
            <span className="field__label">Tapez SUPPRIMER pour confirmer</span>
            <input
              className="input"
              value={confirm}
              autoComplete="off"
              autoCapitalize="characters"
              onChange={(e) => setConfirm(e.target.value)}
            />
          </label>
          {needsPin && (
            <label className="field">
              <span className="field__label">Code du responsable</span>
              <input
                className="input"
                type="password"
                inputMode="numeric"
                autoComplete="off"
                maxLength={6}
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, '').slice(0, 6))}
              />
            </label>
          )}
          {error && (
            <Notice tone="danger">
              <p>{error}</p>
            </Notice>
          )}
          <div className="dialog__actions">
            <Button variant="secondary" disabled={busy} onClick={() => setOpen(false)} autoFocus>
              Garder mon compte
            </Button>
            <Button
              variant="danger"
              solid
              busy={busy}
              disabled={!ready || busy}
              onClick={() => void submit()}
            >
              Programmer la suppression
            </Button>
          </div>
        </div>
      </Dialog>
    </Sheet>
  )
}
