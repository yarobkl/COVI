import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { approveManualCheckoutOrder } from '../../lib/manualOrder'
import { getPendingPublicOrders } from '../../lib/publicOrders'
import { PublicOrderInbox } from './PublicOrderInbox'

vi.mock('../../lib/publicOrders', () => ({
  getPendingPublicOrders: vi.fn(),
}))
vi.mock('../../lib/manualOrder', () => ({
  approveManualCheckoutOrder: vi.fn(),
}))
vi.mock('./CashierCheckoutPanel', () => ({
  CashierCheckoutPanel: ({ orderId }: { orderId: string }) => <p>Encaissement {orderId}</p>,
}))

const shopId = '11111111-1111-4111-8111-111111111111'
const orderId = 'bbbbbbbb-0000-4000-8000-000000000001'
const rows = [
  {
    orderId,
    channel: 'social' as const,
    status: 'submitted' as const,
    amountXaf: 7000,
    customerPhone: '+242 060000000',
    customerNote: 'Robe du live',
    fulfillment: 'pickup' as const,
    createdAt: '2026-10-12T12:00:00Z',
    lines: [{ label: 'Robes', quantity: 2, lineTotalXaf: 7000 }],
  },
]

beforeEach(() => {
  vi.mocked(getPendingPublicOrders).mockReset()
  vi.mocked(approveManualCheckoutOrder).mockReset()
  vi.mocked(getPendingPublicOrders).mockResolvedValue(rows)
})
afterEach(cleanup)

describe('shop owner QR/social requests inbox', () => {
  it('waits for authenticated approval before opening manual cashier', async () => {
    vi.mocked(approveManualCheckoutOrder).mockResolvedValue({
      orderId,
      status: 'approved',
      amountXaf: 7000,
    })
    render(<PublicOrderInbox shopId={shopId} shopName="Boutique A" />)
    await screen.findByText('Robe du live', { exact: false })
    expect(screen.queryByText(/Encaissement bbbbbbbb/)).toBeNull()
    expect(screen.getByText(/Vérifiez vous-même la disponibilité/)).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /Approuver et passer/ }))
    await waitFor(() => expect(screen.getByText('Encaissement ' + orderId)).toBeTruthy())
    expect(approveManualCheckoutOrder).toHaveBeenCalledWith({ shopId, orderId })
  })

  it('never opens payment after a failed approval or wrong total', async () => {
    vi.mocked(approveManualCheckoutOrder).mockResolvedValue({
      orderId,
      status: 'approved',
      amountXaf: 1,
    })
    render(<PublicOrderInbox shopId={shopId} shopName="Boutique A" />)
    await screen.findByText('Robe du live', { exact: false })
    fireEvent.click(screen.getByRole('button', { name: /Approuver et passer/ }))
    await waitFor(() =>
      expect(screen.getByRole('alert').textContent).toContain('ne correspond pas'),
    )
    expect(screen.queryByText('Encaissement ' + orderId)).toBeNull()
  })
})
