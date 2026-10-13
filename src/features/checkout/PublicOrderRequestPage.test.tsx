import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { getPublicCatalog, submitPublicOrder } from '../../lib/publicOrders'
import { PublicOrderRequestPage } from './PublicOrderRequestPage'

vi.mock('./TurnstileChallenge', () => ({
  TurnstileChallenge: ({ onTokenChange }: { onTokenChange: (token: string) => void }) => (
    <button type="button" onClick={() => onTokenChange('test-challenge-token-123456')}>
      Vérifier que je ne suis pas un robot
    </button>
  ),
}))

vi.mock('../../lib/publicOrders', async (original) => ({
  ...(await original<typeof import('../../lib/publicOrders')>()),
  getPublicCatalog: vi.fn(),
  submitPublicOrder: vi.fn(),
}))

const token = 'dddddddd-0000-4000-8000-000000000001'
const categoryId = 'aaaaaaaa-0000-4000-8000-000000000001'
const orderId = 'bbbbbbbb-0000-4000-8000-000000000001'
const trackingToken = 'eeeeeeee-0000-4000-8000-000000000001'

beforeEach(() => {
  vi.mocked(getPublicCatalog).mockReset()
  vi.mocked(submitPublicOrder).mockReset()
  vi.stubGlobal('crypto', {
    randomUUID: () => '77770000-0000-4000-8000-000000000001',
  })
  vi.mocked(getPublicCatalog).mockResolvedValue({
    shopName: 'Chez Mama',
    categories: [{ id: categoryId, label: 'Robes' }],
  })
})
afterEach(() => {
  cleanup()
  vi.unstubAllGlobals()
  window.history.replaceState(null, '', '#/')
})

async function fill() {
  await screen.findByRole('heading', { name: 'Chez Mama' })
  fireEvent.change(screen.getByLabelText('Catégorie'), { target: { value: categoryId } })
  fireEvent.change(screen.getByLabelText('Prix discuté par pièce'), { target: { value: '3500' } })
  fireEvent.click(screen.getByRole('button', { name: 'Ajouter à la demande' }))
  fireEvent.click(screen.getByRole('radio', { name: 'Espèces' }))
  fireEvent.click(screen.getByRole('button', { name: /Vérifier que je ne suis pas un robot/ }))
}

describe('anonymous QR/social notebook request screen', () => {
  it('does not display a payment receipt or deduct stock when request is submitted', async () => {
    vi.mocked(submitPublicOrder).mockResolvedValue({
      orderId,
      trackingToken,
      status: 'submitted',
      amountXaf: 3500,
    })
    render(<PublicOrderRequestPage token={token} channel="qr" />)
    await fill()
    expect(screen.getByText(/Ceci est une demande, pas un paiement/)).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /Envoyer la demande/ }))
    await screen.findByRole('heading', { name: 'Demande envoyée' })
    expect(screen.getByText('BBBBBBBB')).toBeTruthy()
    expect(window.location.hash).toContain('/suivi/' + trackingToken)
    expect(screen.getByText(/Aucun paiement ne peut être effectué depuis cette page/)).toBeTruthy()
    expect(submitPublicOrder).toHaveBeenCalledWith(
      expect.objectContaining({
        token,
        channel: 'qr',
        paymentMethod: 'cash',
        operationId: '77770000-0000-4000-8000-000000000001',
      }),
    )
  })

  it('requires a contact phone when delivery is selected', async () => {
    render(<PublicOrderRequestPage token={token} channel="social" />)
    await fill()
    fireEvent.click(screen.getByLabelText('Livraison'))
    const send = screen.getByRole('button', { name: /Envoyer la demande/ }) as HTMLButtonElement
    expect(send.disabled).toBe(true)
    fireEvent.change(screen.getByLabelText('Votre téléphone'), { target: { value: '+242 0612' } })
    expect(send.disabled).toBe(true)
    fireEvent.change(screen.getByLabelText('Adresse de livraison'), {
      target: { value: 'Brazzaville, Poto-Poto, rue principale' },
    })
    expect(send.disabled).toBe(false)
  })

  it('retains the operation UUID when retrying after a network loss', async () => {
    vi.mocked(submitPublicOrder)
      .mockRejectedValueOnce(new Error('Réseau perdu'))
      .mockResolvedValueOnce({ orderId, trackingToken, status: 'submitted', amountXaf: 3500 })
    render(<PublicOrderRequestPage token={token} channel="social" />)
    await fill()
    fireEvent.click(screen.getByRole('button', { name: /Envoyer la demande/ }))
    await waitFor(() => expect(screen.getByRole('alert').textContent).toContain('Réseau'))
    fireEvent.click(screen.getByRole('button', { name: /Vérifier que je ne suis pas un robot/ }))
    fireEvent.click(screen.getByRole('button', { name: /Envoyer la demande/ }))
    await screen.findByRole('heading', { name: 'Demande envoyée' })
    expect(submitPublicOrder).toHaveBeenCalledTimes(2)
    const calls = vi.mocked(submitPublicOrder).mock.calls
    expect(calls[0][0].operationId).toBe(calls[1][0].operationId)
  })
})
