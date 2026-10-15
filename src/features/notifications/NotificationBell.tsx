import { useId, useState } from 'react'
import { routeHash } from '../../app/routes'
import { BellIcon } from '../../components/icons'
import { Dialog, Ledger, LedgerRow } from '../../components/ui'
import { whenLabel } from '../../lib/dates'
import type { NotificationKind } from '../../lib/notifications'
import type { ShopNotificationsState } from './useShopNotifications'

const kindLabels: Record<NotificationKind, string> = {
  order: 'Commande',
  stock: 'Stock',
  pin: 'Code PIN',
  test: 'Test',
  anomaly: 'À vérifier',
}

/**
 * La cloche de la boutique : pastille du nombre d'alertes non lues, et la liste écrite comme une
 * page du cahier. Ouvrir la liste marque tout comme lu (sur ce téléphone).
 */
export function NotificationBell({
  state,
  className,
  withLabel = false,
}: {
  state: ShopNotificationsState
  className?: string
  /** Sommaire de l'ordinateur : le mot « Notifications » à côté de la cloche. */
  withLabel?: boolean
}) {
  const titleId = useId()
  const { items, failed, seen, refresh, markAllSeen } = state
  const [open, setOpen] = useState(false)

  const unread = (items ?? []).filter((n) => !seen.has(n.id)).length

  const show = () => {
    setOpen(true)
    refresh()
  }
  const close = () => {
    setOpen(false)
    markAllSeen()
  }

  return (
    <>
      <button
        type="button"
        className={['bell', className].filter(Boolean).join(' ')}
        aria-haspopup="dialog"
        aria-label={unread > 0 ? `Notifications : ${unread} non lues` : 'Notifications'}
        onClick={show}
      >
        <BellIcon />
        {withLabel && <span className="bell__label">Notifications</span>}
        {unread > 0 && (
          <span className="bell__count" aria-hidden="true">
            {unread > 9 ? '9+' : unread}
          </span>
        )}
      </button>

      <Dialog open={open} onClose={close} labelledBy={titleId} sheet>
        <div className="dialog__body notifications">
          <h2 className="dialog__title" id={titleId}>
            Notifications
          </h2>
          {items === null ? (
            <p className="muted" role="status">
              {failed ? 'Pas de connexion : réessayez quand le réseau revient.' : 'Chargement…'}
            </p>
          ) : items.length === 0 ? (
            <p className="notifications__empty hand">Rien à signaler. Tout est en ordre.</p>
          ) : (
            <Ledger label="Notifications de la boutique">
              {items.map((n) => (
                <LedgerRow
                  key={n.id}
                  variant="link"
                  className={seen.has(n.id) ? undefined : 'notifications__unread'}
                  label={
                    <a href={routeHash({ page: n.page })} onClick={close}>
                      {n.title}
                    </a>
                  }
                  meta={n.detail}
                  value={
                    <span className="notifications__when">
                      <span className="notifications__kind hand">{kindLabels[n.kind]}</span>
                      {whenLabel(new Date(n.at))}
                    </span>
                  }
                />
              ))}
            </Ledger>
          )}
          <div className="dialog__actions">
            <button type="button" className="btn btn--secondary" onClick={close}>
              Fermer
            </button>
          </div>
        </div>
      </Dialog>
    </>
  )
}
