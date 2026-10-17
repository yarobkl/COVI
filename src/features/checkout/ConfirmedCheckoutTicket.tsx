import { Ticket, TicketLine } from '../../components/ui'
import { fcfa } from '../../lib/format'
import type { ManualPaymentMethod } from '../../lib/orderLifecycle'

const methodNames: Record<ManualPaymentMethod, string> = {
  cash: 'Espèces',
  mobile_money: 'Mobile Money',
  other: 'Autre',
}

export type ConfirmedCheckoutReceipt = {
  shopName: string
  receiptNumber: string
  confirmedAt: string
  cashierFirstName: string
  method: ManualPaymentMethod
  amountXaf: number
  lines: ReadonlyArray<{ label: string; quantity: number; lineTotalXaf: number }>
}

/** "Le Cahier" receipt. Only render AFTER the server has persisted the sale.
 * In particular, receiptNumber and cashierFirstName come from the saved record.
 */
export function ConfirmedCheckoutTicket({ receipt }: { receipt: ConfirmedCheckoutReceipt }) {
  return (
    <Ticket
      head={receipt.shopName}
      sub={receipt.receiptNumber + ' · ' + new Date(receipt.confirmedAt).toLocaleString('fr-FR')}
    >
      {receipt.lines.map((line, index) => (
        <TicketLine
          key={index + '-' + line.label}
          left={line.quantity + ' × ' + line.label}
          right={fcfa(line.lineTotalXaf)}
        />
      ))}
      <hr className="ticket__cut" />
      <TicketLine
        className="ticket__total"
        left="TOTAL"
        right={fcfa(receipt.amountXaf) + ' FCFA'}
      />
      <p className="ticket__note">
        Paiement confirmé par le vendeur · {methodNames[receipt.method]}
      </p>
      <p className="ticket__note">Encaissé par : {receipt.cashierFirstName}</p>
    </Ticket>
  )
}
