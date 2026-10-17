import { useCallback, useEffect, useState } from 'react'
import { Button, Notice, Stamp, Ticket, TicketLine } from '../../components/ui'
import { money } from '../../lib/format'
import {
  fetchOrderStatus,
  paymentMethodLabels,
  statusLabels,
  type PublicOrderStatus,
} from '../../lib/publicOrders'
import { GuestSheet } from './GuestSheet'

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
      <GuestSheet>
        <section className="order-guest__part">
          <h1 className="section-title">Suivi de commande</h1>
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
            <p className="hand order-guest__loading" role="status">
              Chargement…
            </p>
          )}
        </section>
      </GuestSheet>
    )

  const receipt = order.receipt
  return (
    <GuestSheet shop={order.shopName}>
      <section className="order-guest__part">
        <h1 className="section-title">
          Commande <span className="figures">{order.reference}</span>
        </h1>
        <p className={`order-status order-status--${order.status}`}>{statusLabels[order.status]}</p>
        {order.status === 'rejected' && order.rejectReason && <p>Motif : {order.rejectReason}</p>}
        {order.status !== 'paid' && order.status !== 'rejected' && (
          <p className="order-guest__lead">
            Règlement choisi : {paymentMethodLabels[order.paymentMethod]}. Il n’est considéré comme
            reçu que lorsque la boutique l’a confirmé.
          </p>
        )}
        {!receipt && (
          <ul className="order-guest__summary">
            {order.lines.map((l, i) => (
              <li key={i}>
                {l.quantity} × {l.label}
                {l.unitPriceXaf != null && (
                  <span className="figures"> — {money(l.unitPriceXaf)}</span>
                )}
              </li>
            ))}
          </ul>
        )}
        <p className="muted">Envoyée le {dateTime(order.createdAt)}</p>
      </section>

      {receipt && (
        <section className="order-guest__part order-receipt" aria-label="Reçu">
          <h2 className="section-title">Votre reçu</h2>
          <div className="order-receipt__paper">
            <Ticket
              tilt
              head={`Reçu n° ${receipt.receiptNumber}`}
              sub={`${order.shopName} · ${dateTime(receipt.confirmedAt)}`}
            >
              {receipt.lines.map((l, i) => (
                <TicketLine
                  key={i}
                  left={`${l.quantity} × ${l.label}`}
                  right={money(l.unitPriceXaf * l.quantity)}
                />
              ))}
              <hr className="ticket__cut" />
              <TicketLine
                className="ticket__total"
                left="Total réglé"
                right={money(receipt.totalXaf)}
              />
              <p className="ticket__sub">
                {paymentMethodLabels[receipt.method]}, confirmé par la boutique
                {receipt.cashierName ? ` (caisse de ${receipt.cashierName})` : ''}.
              </p>
            </Ticket>
            <Stamp kind="paid">Payé</Stamp>
          </div>
          <Button variant="secondary" onClick={() => window.print()}>
            Imprimer le reçu
          </Button>
        </section>
      )}
    </GuestSheet>
  )
}
