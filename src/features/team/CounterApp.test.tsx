import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCounterMode, enterCounterMode } from '../../lib/counterMode'
import type { TillSession } from '../../lib/team'
import { clearTillSession, setTillSession } from '../../lib/tillSession'
import type { Shop } from '../../lib/types'
import { CounterGate } from './CounterGate'

vi.mock('./CounterApp', () => ({
  CounterApp: () => <p>Caisse par code PIN personnel</p>,
}))

const shop: Shop = {
  id: 'shop-1',
  name: 'Chez Mama Grâce',
  city: 'Brazzaville',
  country: 'République du Congo',
  currency: 'XAF',
}
const till: TillSession = {
  shopId: 'shop-1',
  memberId: 'm-awa',
  displayName: 'Awa',
  maxDiscountPct: 10,
  token: 'c'.repeat(64),
  expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  sellerId: 'u-awa',
  canViewShopSales: false,
}
const signOut = vi.fn().mockResolvedValue(undefined)
const mount = () =>
  render(
    <CounterGate shop={shop} userId="u-manager" signOut={signOut}>
      <a href="#/stock">Gestion du magasin</a>
    </CounterGate>,
  )

beforeEach(() => {
  signOut.mockClear()
  sessionStorage.clear()
  localStorage.clear()
  clearTillSession()
  clearCounterMode()
})
afterEach(() => {
  cleanup()
  clearTillSession()
  clearCounterMode()
})

describe('Shared shop account: PIN cashier selection without signout', () => {
  it('shows management normally before entering checkout', () => {
    mount()
    expect(screen.getByRole('link', { name: 'Gestion du magasin' })).toBeTruthy()
    expect(signOut).not.toHaveBeenCalled()
  })

  it('switches to the cashier PIN interface instead of signing out', () => {
    enterCounterMode(shop.id)
    mount()
    expect(screen.getByText('Caisse par code PIN personnel')).toBeTruthy()
    expect(screen.queryByRole('link', { name: 'Gestion du magasin' })).toBeNull()
    expect(signOut).not.toHaveBeenCalled()
  })

  it('restores the till after a page refresh without logging out', () => {
    setTillSession(till)
    mount()
    expect(screen.getByText('Caisse par code PIN personnel')).toBeTruthy()
    expect(signOut).not.toHaveBeenCalled()
  })
})
