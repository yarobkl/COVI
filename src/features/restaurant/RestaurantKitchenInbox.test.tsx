import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { requestKitchenBrowserAlerts } from '../../lib/kitchenBrowserNotifications'
import { RestaurantKitchenInbox } from './RestaurantKitchenInbox'

vi.mock('../../lib/supabase', () => ({
  supabase: { rpc: vi.fn(async () => ({ data: {}, error: null })) },
}))
vi.mock('../../lib/kitchenInbox', () => ({
  readKitchenInbox: vi.fn(() => ({ events: [], more: false })),
  newlyArrivedKitchenCount: vi.fn(() => ({ newest: null, count: 0 })),
}))
vi.mock('../../lib/kitchenBrowserNotifications', () => ({
  requestKitchenBrowserAlerts: vi.fn(),
  revokeKitchenBrowserAlerts: vi.fn(),
  showKitchenBrowserAlert: vi.fn(),
}))

const request = vi.mocked(requestKitchenBrowserAlerts)

afterEach(() => {
  cleanup()
  request.mockReset()
})

describe('RestaurantKitchenInbox — activation des notifications', () => {
  it('allows retry after local-only mode without claiming remote delivery', async () => {
    request.mockResolvedValueOnce('browser').mockResolvedValueOnce('push')
    render(<RestaurantKitchenInbox shopId="shop-kitchen-1" />)

    fireEvent.click(screen.getByRole('button', { name: 'Autoriser les notifications Cuisine' }))
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Réessayer le Web Push' })).toBeTruthy(),
    )
    expect(
      (screen.getByRole('button', { name: 'Réessayer le Web Push' }) as HTMLButtonElement).disabled,
    ).toBe(false)
    expect(screen.getByText(/Vous pourrez réessayer le Web Push/)).toBeTruthy()

    fireEvent.click(screen.getByRole('button', { name: 'Réessayer le Web Push' }))
    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Abonnement Web Push enregistré' })).toBeTruthy(),
    )
    expect(
      (screen.getByRole('button', { name: 'Abonnement Web Push enregistré' }) as HTMLButtonElement)
        .disabled,
    ).toBe(true)
    expect(screen.getByText(/livraison dépend encore de l’activation du serveur/)).toBeTruthy()
    expect(request).toHaveBeenCalledTimes(2)
    expect(request).toHaveBeenCalledWith('shop-kitchen-1')
  })
})
