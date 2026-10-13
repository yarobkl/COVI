import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { approveManualCheckoutOrder, rejectCheckoutOrder } from '../../lib/manualOrder'
import { getPendingPublicOrders } from '../../lib/publicOrders'
import { watchCheckoutOrderUpdates } from '../../lib/checkoutInboxUpdates'
import { PublicOrderInbox } from './PublicOrderInbox'

vi.mock('../../lib/publicOrders', () => ({
  getPendingPublicOrders: vi.fn(),
}))
vi.mock('../../lib/manualOrder', () => ({
  approveManualCheckoutOrder: vi.fn(),
  rejectCheckoutOrder: vi.fn(),
}))
vi.mock('../../lib/checkoutInboxUpdates', () => ({
  watchCheckoutOrderUpdates: vi.fn(() => () => undefined),
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
  vi.mocked(watchCheckoutOrderUpdates).mockClear()
  vi.mocked(approveManualCheckoutOrder).mockReset()
  vi.mocked(rejectCheckoutOrder).mockReset()
  vi.mocked(getPendingPublicOrders).mockResolvedValue(rows)
})
afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

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

  it('allows the merchant to refuse a proposal without opening the cashier', async () => {
    vi.stubGlobal(
      'confirm',
      vi.fn(() => true),
    )
    vi.mocked(rejectCheckoutOrder).mockResolvedValue({
      orderId,
      status: 'cancelled',
      amountXaf: 7000,
    })
    render(<PublicOrderInbox shopId={shopId} shopName="Boutique A" />)
    await screen.findByText('Robe du live', { exact: false })
    fireEvent.click(screen.getByRole('button', { name: 'Refuser cette demande' }))

    await waitFor(() => expect(rejectCheckoutOrder).toHaveBeenCalledWith({ shopId, orderId }))
    expect(screen.getByText(/Demande refusée/)).toBeTruthy()
    expect(screen.queryByText(/Encaissement bbbbbbbb/)).toBeNull()
    expect(screen.queryByText('Robe du live', { exact: false })).toBeNull()
  })

  it('keeps an order visible if refusal fails', async () => {
    vi.stubGlobal(
      'confirm',
      vi.fn(() => true),
    )
    vi.mocked(rejectCheckoutOrder).mockRejectedValue(new Error('Accès refusé'))
    render(<PublicOrderInbox shopId={shopId} shopName="Boutique A" />)
    await screen.findByText('Robe du live', { exact: false })
    fireEvent.click(screen.getByRole('button', { name: 'Refuser cette demande' }))
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('Accès refusé'))
    expect(screen.getByText('Robe du live', { exact: false })).toBeTruthy()
  })
  it('refreshes the private inbox on Realtime change signals without trusting event payload', async () => {
    const nextId = 'bbbbbbbb-0000-4000-8000-000000000002'
    const nextRows = [{ ...rows[0], orderId: nextId, customerNote: 'Nouveau client' }]
    vi.mocked(getPendingPublicOrders).mockResolvedValueOnce(rows).mockResolvedValueOnce(nextRows)
    let notify: (() => void) | undefined
    vi.mocked(watchCheckoutOrderUpdates).mockImplementation((_shop, callback) => {
      notify = callback
      return () => undefined
    })
    render(<PublicOrderInbox shopId={shopId} shopName="Boutique A" />)
    await screen.findByText('Robe du live', { exact: false })
    expect(notify).toBeTypeOf('function')
    notify?.()
    await screen.findByText('Nouveau client', { exact: false })
    expect(getPendingPublicOrders).toHaveBeenCalledTimes(2)
    expect(getPendingPublicOrders).toHaveBeenNthCalledWith(2, shopId)
  })
})
