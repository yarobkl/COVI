import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCounterMode, isCounterMode } from '../../lib/counterMode'
import { listShopMembers, ownerPinStatus } from '../../lib/team'
import { listSharedCashiers } from '../../lib/sharedCashiers'
import { TillSwitch } from './TillSwitch'

let pending = 0
vi.mock('../sync/useSyncState', () => ({
  useSyncState: () => ({ online: true, pending, rejected: 0 }),
}))
vi.mock('../../lib/sharedCashiers', () => ({
  listSharedCashiers: vi.fn(),
}))
vi.mock('../../lib/team', () => ({
  ownerPinStatus: vi.fn(),
  listShopMembers: vi.fn(),
  teamErrorMessage: () => 'Impossible de charger l’équipe.',
}))
vi.mock('./OwnerPinScreens', () => ({
  OwnerPinSetup: ({ onDone }: { onDone: () => void }) => (
    <button onClick={onDone}>Enregistrer mon code responsable</button>
  ),
}))

beforeEach(() => {
  pending = 0
  localStorage.clear()
  clearCounterMode()
  vi.mocked(ownerPinStatus).mockResolvedValue({ pin_set: true, locked_until: null })
  vi.mocked(listSharedCashiers).mockResolvedValue([])
  vi.mocked(listShopMembers).mockResolvedValue([
    { id: 'm-awa', active: true, pin_set: true, pin_must_change: false },
  ] as Awaited<ReturnType<typeof listShopMembers>>)
})
afterEach(() => {
  cleanup()
  vi.clearAllMocks()
  clearCounterMode()
})

describe('Gestion partagée → caisse par PIN, sans déconnexion', () => {
  it('starts cashier selection without signing out the management account', async () => {
    render(<TillSwitch shopId="shop-1" />)
    fireEvent.click(screen.getByRole('button', { name: 'Choisir un caissier' }))
    await waitFor(() => expect(isCounterMode('shop-1')).toBe(true))
    expect(ownerPinStatus).toHaveBeenCalledWith('shop-1')
    expect(screen.queryByText('Déconnecter le responsable')).toBeNull()
  })

  it('blocks cashier switching when sales are waiting for sync', () => {
    pending = 2
    render(<TillSwitch shopId="shop-1" />)
    const button = screen.getByRole('button', { name: 'Choisir un caissier' })
    expect((button as HTMLButtonElement).disabled).toBe(true)
    fireEvent.click(button)
    expect(isCounterMode('shop-1')).toBe(false)
    expect(ownerPinStatus).not.toHaveBeenCalled()
  })

  it('requires at least one cashier with a personal PIN', async () => {
    vi.mocked(listShopMembers).mockResolvedValue([])
    render(<TillSwitch shopId="shop-1" />)
    fireEvent.click(screen.getByRole('button', { name: 'Choisir un caissier' }))
    expect(await screen.findByText(/Aucun caissier prêt/)).toBeTruthy()
    expect(isCounterMode('shop-1')).toBe(false)
  })

  it('sets up a responsible PIN once before entering the till', async () => {
    vi.mocked(ownerPinStatus).mockResolvedValue({ pin_set: false, locked_until: null })
    render(<TillSwitch shopId="shop-1" />)
    fireEvent.click(screen.getByRole('button', { name: 'Choisir un caissier' }))
    await screen.findByRole('button', { name: 'Enregistrer mon code responsable' })
    expect(isCounterMode('shop-1')).toBe(false)
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Enregistrer mon code responsable' }))
    })
    expect(isCounterMode('shop-1')).toBe(true)
  })
})
