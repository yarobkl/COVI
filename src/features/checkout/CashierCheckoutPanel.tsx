import { useRef, useState } from 'react'
import { Stamp } from '../../components/ui'
import { ReceiptPdfActions } from './ReceiptPdfActions'
import { CashierPaymentConfirmationForm } from './CashierPaymentConfirmationForm'
import { ConfirmedCheckoutTicket } from './ConfirmedCheckoutTicket'
import {
  confirmManualCheckoutPayment,
  type RecordedCheckoutReceipt,
} from '../../lib/manualCheckout'
import type { ManualCashierAttestation } from '../../lib/orderLifecycle'

/**
 * Prepared integration of the manual payment form with the atomic server RPC.
 * NOT mounted in Root, routes or the existing SalePage.
 * It becomes usable only after the SQL migrations and access tests are approved.
 */
type Props = {
  shopId: string
  shopName: string
  orderId: string
  amountXaf: number
  verifiedCashierFirstName?: string
  requirePin?: boolean
}

export function CashierCheckoutPanel(props: Props) {
  // React remounts the inner form when the order changes. A receipt or an
  // operation identifier from one order must never leak into another order.
  return <CashierCheckoutPanelInstance key={props.shopId + ':' + props.orderId} {...props} />
}

function CashierCheckoutPanelInstance({
  shopId,
  shopName,
  orderId,
  amountXaf,
  verifiedCashierFirstName,
  requirePin,
}: Props) {
  const [receipt, setReceipt] = useState<RecordedCheckoutReceipt | null>(null)

  // A lost network response may be retried with the SAME operation ID only
  // when the complete user attestation remains unchanged.
  const attempt = useRef<{ fingerprint: string; operationId: string } | null>(null)

  async function onConfirm(attestation: ManualCashierAttestation) {
    const fingerprint = JSON.stringify([shopId, orderId, attestation])
    if (!attempt.current || attempt.current.fingerprint !== fingerprint) {
      attempt.current = { fingerprint, operationId: crypto.randomUUID() }
    }

    const confirmed = await confirmManualCheckoutPayment({
      shopId,
      orderId,
      operationId: attempt.current.operationId,
      attestation,
    })
    // Use only the fields saved by the server to show the receipt.
    setReceipt(confirmed)
  }

  if (receipt) {
    return (
      <section className="sheet checkout-receipt" aria-label="Reçu de vente enregistré">
        <header className="checkout-receipt__head">
          <h2>Vendu.</h2>
          <Stamp kind="paid" size="sm">
            Payé
          </Stamp>
        </header>
        <p className="hand checkout-receipt__hand">C'est noté dans le cahier.</p>
        <p className="checkout-receipt__status" role="status">
          Paiement déclaré reçu par le vendeur. La vente et son reçu ont été enregistrés.
        </p>
        <ConfirmedCheckoutTicket
          receipt={{
            shopName,
            receiptNumber: receipt.receiptNumber,
            confirmedAt: receipt.confirmedAt,
            cashierFirstName: receipt.cashierFirstName,
            method: receipt.method,
            amountXaf: receipt.amountXaf,
            lines: receipt.lines,
          }}
        />
        <ReceiptPdfActions receipt={{
          shopName,
          receiptNumber: receipt.receiptNumber,
          confirmedAt: receipt.confirmedAt,
          cashierFirstName: receipt.cashierFirstName,
          method: receipt.method,
          amountXaf: receipt.amountXaf,
          lines: receipt.lines,
        }} />
      </section>
    )
  }

  return (
    <CashierPaymentConfirmationForm
      amountXaf={amountXaf}
      onConfirm={onConfirm}
      verifiedCashierFirstName={verifiedCashierFirstName}
      requirePin={requirePin}
    />
  )
}
