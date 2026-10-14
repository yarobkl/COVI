import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCounterMode, enterCounterMode } from '../../lib/counterMode'
import type { TillSession } from '../../lib/team'
import { clearTillSession, setTillSession } from '../../lib/tillSession'
import type { Shop } from '../../lib/types'
import { CounterGate } from './CounterGate'

let pending = 0
vi.mock('../sync/useSyncState', () => ({
  useSyncState: () => ({ online: true, pending, rejected: 0 }),
}))

const shop: Shop = {
  id: 'shop-1',
  name: 'Chez Mama Grâce',
  city: 'Brazzaville',
  country: 'République du Congo',
  currency: 'XAF',
}
const legacy: TillSession = {
  shopId: 'shop-1',
  memberId: 'm-awa',
  displayName: 'Awa',
  maxDiscountPct: 10,
  token: 'c'.repeat(64),
  expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  sellerId: 'u-awa',
  canViewShopSales: false,
}

function renderGate(signOut: () => Promise<void>) {
  return render(
    <CounterGate shop={shop} userId="u-owner" signOut={signOut}>
      <a href="#/stock">Stock du responsable</a>
    </CounterGate>,
  )
}

beforeEach(() => {
  pending = 0
  sessionStorage.clear()
  localStorage.clear()
  clearTillSession()
  clearCounterMode()
})
afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
})

describe('Retiring unsafe owner-JWT shared counter sessions', () => {
  it('shows the owner app normally with no legacy counter', () => {
    const signOut = vi.fn().mockResolvedValue(undefined)
    renderGate(signOut)
    expect(screen.getByRole('link', { name: 'Stock du responsable' })).toBeTruthy()
    expect(signOut).not.toHaveBeenCalled()
  })

  it('signs out legacy tills without revealing owner pages', async () => {
    setTillSession(legacy)
    const signOut = vi.fn().mockResolvedValue(undefined)
    renderGate(signOut)
    expect(screen.queryByRole('link', { name: 'Stock du responsable' })).toBeNull()
    expect(screen.getByText('Caisse sur appareil partagé')).toBeTruthy()
    await waitFor(() => expect(signOut).toHaveBeenCalledTimes(1))
    expect(screen.queryByRole('button', { name: 'Ouvrir sa caisse' })).toBeNull()
  })

  it('blocks automatic logout while an offline sale needs syncing', () => {
    pending = 1
    enterCounterMode(shop.id)
    const signOut = vi.fn().mockResolvedValue(undefined)
    renderGate(signOut)
    expect(screen.queryByRole('link', { name: 'Stock du responsable' })).toBeNull()
    expect(screen.getByText(/1 vente\(s\) en attente/)).toBeTruthy()
    expect(
      (screen.getByRole('button', { name: 'Réessayer la déconnexion' }) as HTMLButtonElement)
        .disabled,
    ).toBe(true)
    expect(signOut).not.toHaveBeenCalled()
  })

  it('allows a safe retry if the first signout fails', async () => {
    enterCounterMode(shop.id)
    const signOut = vi
      .fn()
      .mockRejectedValueOnce(new Error('offline'))
      .mockResolvedValueOnce(undefined)
    renderGate(signOut)
    await waitFor(() =>
      expect(screen.getByText(/La déconnexion du responsable a échoué/)).toBeTruthy(),
    )
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Réessayer la déconnexion' }))
    })
    expect(signOut).toHaveBeenCalledTimes(2)
  })
})
