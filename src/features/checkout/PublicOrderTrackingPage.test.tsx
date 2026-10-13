import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { getGuestCheckoutStatus } from '../../lib/publicOrders'
import { downloadConfirmedReceiptPdf } from '../../lib/receiptPdf'
import { PublicOrderTrackingPage } from './PublicOrderTrackingPage'

vi.mock('../../lib/publicOrders', () => ({
  getGuestCheckoutStatus: vi.fn(),
}))
vi.mock('../../lib/receiptPdf', () => ({
  downloadConfirmedReceiptPdf: vi.fn(),
}))
vi.mock('./ConfirmedCheckoutTicket', () => ({
  ConfirmedCheckoutTicket: ({ receipt }: { receipt: { receiptNumber: string } }) => (
    <p>Reçu : {receipt.receiptNumber}</p>
  ),
}))

const trackingToken = 'eeeeeeee-0000-4000-8000-000000000001'
const orderId = 'bbbbbbbb-0000-4000-8000-000000000001'
const base = {
  shopName: 'YARO BOUTIQUE',
  orderId,
  status: 'submitted' as const,
  amountXaf: 7000,
}

beforeEach(() => {
  vi.mocked(getGuestCheckoutStatus).mockReset()
  vi.mocked(downloadConfirmedReceiptPdf).mockReset()
})
afterEach(cleanup)

describe('customer follow-up using private tracking token', () => {
  it('keeps receipt hidden until payment confirmation', async () => {
    vi.mocked(getGuestCheckoutStatus).mockResolvedValue(base)
    render(<PublicOrderTrackingPage token={trackingToken} />)
    expect(await screen.findByText(/Paiement en attente/)).toBeTruthy()
    expect(screen.queryByRole('button', { name: /Télécharger mon reçu PDF/ })).toBeNull()
    expect(downloadConfirmedReceiptPdf).not.toHaveBeenCalled()
    expect(getGuestCheckoutStatus).toHaveBeenCalledWith(trackingToken)
  })

  it('makes PDF available only with server-confirmed receipt details', async () => {
    vi.mocked(getGuestCheckoutStatus).mockResolvedValue({
      ...base,
      status: 'paid',
      receipt: {
        receiptNumber: 'CV-2026-00042',
        confirmedAt: '2026-10-13T14:00:00Z',
        cashierFirstName: 'Marie',
        method: 'mobile_money',
        amountXaf: 7000,
        lines: [{ label: 'Robes', quantity: 2, lineTotalXaf: 7000 }],
      },
    })
    render(<PublicOrderTrackingPage token={trackingToken} />)
    expect(await screen.findByText('Reçu : CV-2026-00042')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Télécharger mon reçu PDF' }))
    expect(downloadConfirmedReceiptPdf).toHaveBeenCalledWith(
      expect.objectContaining({
        shopName: 'YARO BOUTIQUE',
        receiptNumber: 'CV-2026-00042',
        amountXaf: 7000,
      }),
    )
  })

  it('never offers a receipt for a cancelled request', async () => {
    vi.mocked(getGuestCheckoutStatus).mockResolvedValue({
      ...base,
      status: 'cancelled',
    })
    render(<PublicOrderTrackingPage token={trackingToken} />)
    expect(await screen.findByText(/clôturée sans encaissement/)).toBeTruthy()
    expect(screen.queryByRole('button', { name: /Télécharger mon reçu PDF/ })).toBeNull()
  })
})
