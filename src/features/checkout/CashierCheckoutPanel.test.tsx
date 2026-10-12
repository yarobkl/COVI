import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { confirmManualCheckoutPayment } from '../../lib/manualCheckout'
import { CashierCheckoutPanel } from './CashierCheckoutPanel'

vi.mock('../../lib/manualCheckout', () => ({
  confirmManualCheckoutPayment: vi.fn(),
}))

const recorded = {
  saleId: '76f30e5c-9502-446f-a788-9aed154b61e2',
  receiptNumber: 'CV-2026-000042',
  confirmedAt: '2026-10-12T12:10:00Z',
  cashierFirstName: 'Marie Lou',
  method: 'mobile_money' as const,
  amountXaf: 12000,
  lines: [{ label: 'Robes', quantity: 3, lineTotalXaf: 12000 }],
}

function fill() {
  fireEvent.click(screen.getByLabelText('Mobile Money'))
  fireEvent.change(screen.getByLabelText('Prénom de la personne qui encaisse'), {
    target: { value: 'Marie Lou' },
  })
}

beforeEach(() => {
  vi.stubGlobal('crypto', { randomUUID: () => 'ed203631-32d4-48e0-b6a0-a2fd35f567f4' })
  vi.mocked(confirmManualCheckoutPayment).mockReset()
})
afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

describe('manual checkout RPC integration (not mounted on live routes)', () => {
  it('renders a receipt only after a successful server confirmation', async () => {
    vi.mocked(confirmManualCheckoutPayment).mockResolvedValue(recorded)
    render(<CashierCheckoutPanel
      shopId="shop-1" shopName="Boutique COVI" orderId="order-1" amountXaf={12000}
    />)
    fill()

    expect(screen.queryByText('Encaissé par : Marie Lou')).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer le paiement reçu' }))

    await waitFor(() => expect(screen.getByText('Encaissé par : Marie Lou')).toBeTruthy())
    expect(screen.getByText(/CV-2026-000042/)).toBeTruthy()
    expect(confirmManualCheckoutPayment).toHaveBeenCalledWith({
      shopId: 'shop-1',
      orderId: 'order-1',
      operationId: 'ed203631-32d4-48e0-b6a0-a2fd35f567f4',
      attestation: { method: 'mobile_money', cashierFirstName: 'Marie Lou' },
    })
  })

  it('reuses the same operation ID after a network failure, preventing duplicate sales', async () => {
    vi.mocked(confirmManualCheckoutPayment)
      .mockRejectedValueOnce(new Error('Réseau indisponible'))
      .mockResolvedValueOnce(recorded)

    render(<CashierCheckoutPanel
      shopId="shop-1" shopName="Boutique COVI" orderId="order-1" amountXaf={12000}
    />)
    fill()
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer le paiement reçu' }))
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('Réseau'))

    fireEvent.click(screen.getByRole('button', { name: 'Confirmer le paiement reçu' }))
    await waitFor(() => expect(screen.getByText('Encaissé par : Marie Lou')).toBeTruthy())
    expect(confirmManualCheckoutPayment).toHaveBeenCalledTimes(2)
    expect(vi.mocked(confirmManualCheckoutPayment).mock.calls[0][0].operationId)
      .toBe(vi.mocked(confirmManualCheckoutPayment).mock.calls[1][0].operationId)
  })
})
