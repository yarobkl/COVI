import { afterEach, describe, expect, it } from 'vitest'
import { cleanup, render, screen } from '@testing-library/react'
import { ConfirmedCheckoutTicket } from './ConfirmedCheckoutTicket'

afterEach(cleanup)

describe('confirmed checkout receipt', () => {
  it('shows the cashier first name recorded with the sale', () => {
    render(
      <ConfirmedCheckoutTicket
        receipt={{
          shopName: 'Boutique Test',
          receiptNumber: 'CV-2026-000125',
          confirmedAt: '2026-10-12T12:00:00Z',
          cashierFirstName: 'Marie Lou',
          method: 'mobile_money',
          amountXaf: 7000,
          lines: [{ label: 'Robes', quantity: 2, lineTotalXaf: 7000 }],
        }}
      />,
    )
    expect(screen.getByText('Encaissé par : Marie Lou')).toBeTruthy()
    expect(screen.getByText('Paiement confirmé par le vendeur · Mobile Money')).toBeTruthy()
    expect(screen.getByText(/CV-2026-000125/)).toBeTruthy()
  })
})
