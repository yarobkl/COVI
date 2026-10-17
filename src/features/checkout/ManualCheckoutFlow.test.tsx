import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { listCheckoutStockCategories } from '../../lib/checkoutCategoryStock'
import { approveManualCheckoutOrder, createManualCheckoutOrder } from '../../lib/manualOrder'
import { ManualCheckoutFlow } from './ManualCheckoutFlow'

vi.mock('../../lib/checkoutCategoryStock', () => ({
  listCheckoutStockCategories: vi.fn(),
}))
vi.mock('../../lib/manualOrder', async (importOriginal) => ({
  ...(await importOriginal<typeof import('../../lib/manualOrder')>()),
  createManualCheckoutOrder: vi.fn(),
  approveManualCheckoutOrder: vi.fn(),
}))
vi.mock('./CashierCheckoutPanel', () => ({
  CashierCheckoutPanel: ({ orderId, amountXaf }: { orderId: string; amountXaf: number }) => (
    <p>
      Écran d'encaissement {orderId} · {amountXaf} FCFA
    </p>
  ),
}))

const shopId = '11111111-1111-4111-8111-111111111111'
const robeId = 'aaaaaaaa-0000-4000-8000-000000000001'
const orderId = 'cccccccc-0000-4000-8000-000000000001'

beforeEach(() => {
  vi.mocked(listCheckoutStockCategories).mockReset()
  vi.mocked(createManualCheckoutOrder).mockReset()
  vi.mocked(approveManualCheckoutOrder).mockReset()
  vi.stubGlobal('crypto', {
    randomUUID: () => 'aaaa0000-0000-4000-8000-000000000001',
  })
  vi.mocked(listCheckoutStockCategories).mockResolvedValue([
    { id: robeId, shopId, label: 'Robes', available: 4, isTest: false },
  ])
})
afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
})

async function fillBasket() {
  await screen.findByText('Le panier')
  fireEvent.change(screen.getByLabelText('Catégorie'), { target: { value: robeId } })
  fireEvent.change(screen.getByLabelText('Prix négocié par pièce'), {
    target: { value: '3500' },
  })
  fireEvent.click(screen.getByRole('button', { name: 'Ajouter au panier' }))
}

describe('future COVI manual checkout flow (not mounted on production routes)', () => {
  it('creates, approves and only THEN shows the cashier confirmation', async () => {
    vi.mocked(createManualCheckoutOrder).mockResolvedValue({
      orderId,
      status: 'submitted',
      amountXaf: 3500,
    })
    vi.mocked(approveManualCheckoutOrder).mockResolvedValue({
      orderId,
      status: 'approved',
      amountXaf: 3500,
    })

    render(<ManualCheckoutFlow shopId={shopId} shopName="Boutique A" />)
    await fillBasket()
    expect(screen.queryByText(/Écran d'encaissement/)).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: /Préparer la commande/ }))

    await waitFor(() => expect(screen.getByText(/Écran d'encaissement/)).toBeTruthy())
    expect(listCheckoutStockCategories).toHaveBeenCalledWith(shopId, false)
    expect(createManualCheckoutOrder).toHaveBeenCalledWith({
      shopId,
      operationId: 'aaaa0000-0000-4000-8000-000000000001',
      lines: [{ categoryId: robeId, quantity: 1, negotiatedUnitPriceXaf: 3500 }],
      isTest: false,
      fulfillment: 'pickup',
    })
    expect(approveManualCheckoutOrder).toHaveBeenCalledWith({ shopId, orderId })
  })

  it('preserves creation operation ID on retry after approval network failure', async () => {
    vi.mocked(createManualCheckoutOrder).mockResolvedValue({
      orderId,
      status: 'submitted',
      amountXaf: 3500,
    })
    vi.mocked(approveManualCheckoutOrder)
      .mockRejectedValueOnce(new Error('Connexion perdue'))
      .mockResolvedValueOnce({ orderId, status: 'approved', amountXaf: 3500 })

    render(<ManualCheckoutFlow shopId={shopId} shopName="Boutique A" />)
    await fillBasket()
    fireEvent.click(screen.getByRole('button', { name: /Préparer la commande/ }))
    await screen.findByRole('alert')
    expect(screen.queryByText(/Écran d'encaissement/)).toBeNull()

    fireEvent.click(screen.getByRole('button', { name: /Préparer la commande/ }))
    await waitFor(() => expect(screen.getByText(/Écran d'encaissement/)).toBeTruthy())
    expect(createManualCheckoutOrder).toHaveBeenCalledTimes(2)
    const calls = vi.mocked(createManualCheckoutOrder).mock.calls
    expect(calls[0][0].operationId).toBe(calls[1][0].operationId)
  })

  it('does not proceed to cashier if server totals do not match', async () => {
    vi.mocked(createManualCheckoutOrder).mockResolvedValue({
      orderId,
      status: 'submitted',
      amountXaf: 9999,
    })
    render(<ManualCheckoutFlow shopId={shopId} shopName="Boutique A" />)
    await fillBasket()
    fireEvent.click(screen.getByRole('button', { name: /Préparer la commande/ }))
    expect((await screen.findByRole('alert')).textContent).toContain('ne correspond pas')
    expect(approveManualCheckoutOrder).not.toHaveBeenCalled()
    expect(screen.queryByText(/Écran d'encaissement/)).toBeNull()
  })

  it('reports loading failures without triggering a full-page navigation', async () => {
    vi.mocked(listCheckoutStockCategories)
      .mockRejectedValueOnce(new Error('Connexion indisponible'))
      .mockResolvedValueOnce([])
    render(<ManualCheckoutFlow shopId={shopId} shopName="Boutique A" />)
    await screen.findByText('Connexion indisponible')
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }))
    await screen.findByText('Le panier')
    expect(listCheckoutStockCategories).toHaveBeenCalledTimes(2)
  })
})
