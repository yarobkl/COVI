import { useCallback, useEffect, useState } from 'react'
import { Button, Notice } from '../../components/ui'
import { money } from '../../lib/format'
import {
  fetchOrderStatus,
  paymentMethodLabels,
  statusLabels,
  type PublicOrderStatus,
} from '../../lib/publicOrders'

const dateTime = (iso: string) =>
  new Date(iso).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })

/** Suivi d'une commande par le client (lien reçu après l'envoi) et reçu une fois le règlement confirmé. */
export function PublicTrackingPage({ trackingToken }: { trackingToken: string }) {
  const [order, setOrder] = useState<PublicOrderStatus | null>(null)
  const [error, setError] = useState('')

  const load = useCallback(() => {
    fetchOrderStatus(trackingToken)
      .then((o) => {
        setOrder(o)
        setError('')
      })
      .catch((e: Error) => setError(e.message))
  }, [trackingToken])

  useEffect(() => {
    load()
    // Actualisation automatique tant que la commande n'est pas clôturée.
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') load()
    }, 30_000)
    return () => window.clearInterval(timer)
  }, [load])

  useEffect(() => {
    document.title = order ? `Commande ${order.reference} — ${order.shopName}` : 'Suivi de commande'
  }, [order])

  if (!order)
    return (
      <main className="order-guest" id="contenu">
        <section className="order-guest__card">
          <h1>Suivi de commande</h1>
          {error ? (
            <>
              <Notice tone="danger">
                <p>{error}</p>
              </Notice>
              <Button variant="secondary" onClick={load}>
                Réessayer
              </Button>
            </>
          ) : (
            <p role="status">Chargement…</p>
          )}
        </section>
      </main>
    )

  const receipt = order.receipt
  return (
    <main className="order-guest" id="contenu">
      <section className="order-guest__card">
        <p className="order-guest__shop">{order.shopName}</p>
        <h1>Commande {order.reference}</h1>
        <p className={`order-status order-status--${order.status}`}>{statusLabels[order.status]}</p>
        {order.status === 'rejected' && order.rejectReason && <p>Motif : {order.rejectReason}</p>}
        {order.status !== 'paid' && order.status !== 'rejected' && (
          <p className="muted">
            Règlement choisi : {paymentMethodLabels[order.paymentMethod]}. Il n’est considéré comme
            reçu que lorsque la boutique l’a confirmé.
          </p>
        )}
        {!receipt && (
          <ul className="order-guest__summary">
            {order.lines.map((l, i) => (
              <li key={i}>
                {l.quantity} × {l.label}
                {l.unitPriceXaf != null && ` — ${money(l.unitPriceXaf)}`}
              </li>
            ))}
          </ul>
        )}
        <p className="muted">Envoyée le {dateTime(order.createdAt)}</p>
      </section>

      {receipt && (
        <section className="order-guest__card order-receipt" aria-label="Reçu">
          <h2>Reçu n° {receipt.receiptNumber}</h2>
          <p>
            {order.shopName} · {dateTime(receipt.confirmedAt)}
          </p>
          <ul className="order-guest__summary">
            {receipt.lines.map((l, i) => (
              <li key={i}>
                {l.quantity} × {l.label} — {money(l.unitPriceXaf * l.quantity)}
              </li>
            ))}
          </ul>
          <p className="order-guest__total">
            Total réglé : <b>{money(receipt.totalXaf)}</b>
          </p>
          <p>
            Règlement : {paymentMethodLabels[receipt.method]}, confirmé par la boutique
            {receipt.cashierName ? ` (caisse de ${receipt.cashierName})` : ''}.
          </p>
          <Button variant="secondary" onClick={() => window.print()}>
            Imprimer le reçu
          </Button>
        </section>
      )}
    </main>
  )
}
