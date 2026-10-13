import { useEffect, useState } from 'react'
import { Button, Notice, Sheet } from '../../components/ui'
import { fcfa } from '../../lib/format'
import {
  getGuestCheckoutStatus,
  type GuestCheckoutStatus,
} from '../../lib/publicOrders'
import { downloadConfirmedReceiptPdf } from '../../lib/receiptPdf'
import { ConfirmedCheckoutTicket } from './ConfirmedCheckoutTicket'

/** The private tracking token is unguessable and NOT a shop-wide QR token.
 * No customer identity, phone or private inventory is published by this view.
 */
export function PublicOrderTrackingPage({ token }: { token: string }) {
  const [order, setOrder] = useState<GuestCheckoutStatus | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true
    let inFlight = false
    async function refresh() {
      if (inFlight) return
      inFlight = true
      try {
        const next = await getGuestCheckoutStatus(token)
        if (!active) return
        setOrder(next)
        setError('')
      } catch (reason) {
        if (active)
          setError(reason instanceof Error ? reason.message : 'Suivi temporairement indisponible.')
      } finally {
        inFlight = false
        if (active) setLoading(false)
      }
    }
    void refresh()
    // Poll until the seller confirms payment; the customer's web tab
    // does not require an account or a permanent WebSocket connection.
    const timer = window.setInterval(() => {
      if (document.visibilityState !== 'hidden') void refresh()
    }, 7000)
    return () => {
      active = false
      window.clearInterval(timer)
    }
  }, [token])

  const paid = order?.status === 'paid' && order.receipt
  const closed = order?.status === 'cancelled' || order?.status === 'expired'
  return (
    <main className="checkout-guest seyes margin-rule">
      <Sheet className="checkout-guest__sheet">
        <p className="hand">Suivi de votre commande</p>
        <h1>{order?.shopName ?? 'COVI'}</h1>
        {loading && <p role="status">Chargement de votre commande…</p>}
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        {order && (
          <>
            <p>Commande {order.orderId.slice(0, 8).toUpperCase()}</p>
            <p>Montant proposé : {fcfa(order.amountXaf)} FCFA</p>
            {paid ? (
              <>
                <p role="status">✓ Le commerçant a confirmé la réception de votre paiement.</p>
                <ConfirmedCheckoutTicket
                  receipt={{
                    shopName: order.shopName,
                    receiptNumber: order.receipt!.receiptNumber,
                    confirmedAt: order.receipt!.confirmedAt,
                    cashierFirstName: order.receipt!.cashierFirstName,
                    method: order.receipt!.method,
                    amountXaf: order.receipt!.amountXaf,
                    lines: order.receipt!.lines,
                  }}
                />
                <Button
                  variant="sale"
                  block
                  onClick={() =>
                    downloadConfirmedReceiptPdf({
                      shopName: order.shopName,
                      ...order.receipt!,
                    })
                  }
                >
                  Télécharger mon reçu PDF
                </Button>
                <p className="field__hint">
                  Ce reçu confirme l'encaissement déclaré par la boutique.
                  Les mentions fiscales d'une facture dépendent des informations légales du commerce.
                </p>
              </>
            ) : closed ? (
              <p role="status">Cette demande a été clôturée sans encaissement confirmé.</p>
            ) : (
              <>
                <p role="status">Paiement en attente de confirmation par le commerçant.</p>
                <p>
                  Conservez cette page : son suivi se met à jour automatiquement.
                  Aucun montant n'est débité par COVI depuis cet écran.
                </p>
              </>
            )}
          </>
        )}
      </Sheet>
    </main>
  )
}
