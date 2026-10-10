import { useId, useState } from 'react'
import { CloudOffIcon, CloudUpIcon, InfoIcon } from '../../components/icons'
import { Button, Dialog } from '../../components/ui'
import { whenLabel } from '../../lib/dates'
import { money, paidWith, plural } from '../../lib/format'
import { cachedStock, clearRejectedSaleCount, rejectedSales } from '../../lib/offline'
import { saleErrorMessage } from '../sale/saleErrors'
import type { SyncState } from './useSyncState'

const toSend = (n: number) => `${plural(n, 'vente')} à envoyer`

/**
 * Calm network indicator: nothing when all is well; « Pas de réseau · vous pouvez vendre », « 1
 * vente à envoyer » or « 1 vente non enregistrée · voir » otherwise (never red). Touching it
 * explains what happens.
 */
export function NetStatus({ state, shopId }: { state: SyncState; shopId: string }) {
  const [open, setOpen] = useState(false)
  const titleId = useId()
  const { online, pending, rejected } = state
  if (online && !pending && !rejected) return null

  const showRejected = online && rejected > 0
  const Icon = !online ? CloudOffIcon : showRejected ? InfoIcon : CloudUpIcon
  const label = !online
    ? 'Pas de réseau · vous pouvez vendre'
    : showRejected
      ? `${plural(rejected, 'vente non enregistrée', 'ventes non enregistrées')} · voir`
      : toSend(pending)

  const close = () => {
    if (showRejected) clearRejectedSaleCount()
    setOpen(false)
  }

  return (
    <>
      <button
        type="button"
        className="net-pill"
        aria-haspopup="dialog"
        onClick={() => setOpen(true)}
      >
        <Icon />
        <span>
          {label}
          {!online && pending > 0 && <b className="net-pill__second">{toSend(pending)}</b>}
        </span>
      </button>
      <Dialog open={open} onClose={() => setOpen(false)} labelledBy={titleId} sheet>
        <div className="dialog__body">
          {showRejected ? (
            <RejectedDetail titleId={titleId} shopId={shopId} count={rejected} />
          ) : (
            <>
              <h2 className="dialog__title" id={titleId}>
                {online ? toSend(pending) : 'Pas de réseau en ce moment.'}
              </h2>
              <p className="dialog__text">
                Vous pouvez continuer à vendre : COVI garde vos ventes et les envoie toutes seules
                dès que le réseau revient.
              </p>
              {pending > 0 && (
                <p className="dialog__text">Ne désinstallez pas l’application avant l’envoi.</p>
              )}
            </>
          )}
          <div className="dialog__actions">
            <Button variant="primary" onClick={close}>
              Compris
            </Button>
          </div>
        </div>
      </Dialog>
    </>
  )
}

function RejectedDetail({
  titleId,
  shopId,
  count,
}: {
  titleId: string
  shopId: string
  count: number
}) {
  const names = new Map(
    cachedStock<{ id: string; name: string }>(shopId).map((p) => [p.id, p.name]),
  )
  const sales = rejectedSales().filter((s) => !s.dismissed)
  return (
    <>
      <h2 className="dialog__title" id={titleId}>
        {count > 1
          ? `${count} ventes n’ont pas pu être enregistrées.`
          : 'Une vente n’a pas pu être enregistrée.'}
      </h2>
      {sales.length > 0 && (
        <ul className="rejected-list">
          {sales.map((s) => (
            <li key={s.id}>
              <b>{names.get(s.productId) ?? 'Un article'}</b>, {money(s.soldUnitPrice * s.quantity)}{' '}
              {paidWith(s.paymentLabel)}, {whenLabel(new Date(s.createdAt))}.{' '}
              {saleErrorMessage({ message: s.reason })}
            </li>
          ))}
        </ul>
      )}
      <p className="dialog__text">
        Le stock de ce téléphone a été remis comme avant. Si vous avez bien encaissé cet argent,
        refaites la vente avec un autre article ou notez-le.
      </p>
    </>
  )
}
