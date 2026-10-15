import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { enterCounterMode, isCounterMode } from '../../lib/counterMode'
import type { TillSession } from '../../lib/team'
import { clearTillSession, getTillSession, setTillSession } from '../../lib/tillSession'
import { CounterApp } from './CounterApp'

// The owner's code is checked by the server: here it is simply accepted.
vi.mock('./OwnerPinScreens', () => ({
  OwnerPinPrompt: ({ onLeft }: { onLeft: () => void }) => (
    <button onClick={onLeft}>Code du responsable accepté</button>
  ),
}))
vi.mock('../sale/SalePage', () => ({ SalePage: () => <p>Vendre</p> }))
vi.mock('../orders/OrdersInbox', () => ({ OrdersInbox: () => null }))
vi.mock('../history/HistoryPage', () => ({ HistoryPage: () => null }))

const till: TillSession = {
  shopId: 'shop-1',
  memberId: 'm-awa',
  displayName: 'Awa',
  maxDiscountPct: 0,
  token: 'c'.repeat(64),
  expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  sellerId: 'u-awa',
  canViewShopSales: false,
}

afterEach(() => {
  cleanup()
  clearTillSession()
  window.location.hash = ''
})

describe('Leaving the counter with the owner code', () => {
  it('closes the till and lands on Accueil, not back on Vendre', () => {
    window.location.hash = '#/vendre'
    setTillSession(till)
    enterCounterMode('shop-1')
    render(
      <CounterApp
        shop={{ id: 'shop-1', name: 'Chez Mama Grâce', city: null, country: null, currency: 'XAF' }}
        userId="u-owner"
        signOut={vi.fn()}
      />,
    )
    fireEvent.click(screen.getByRole('button', { name: 'Revenir au responsable' }))
    fireEvent.click(screen.getByRole('button', { name: 'Code du responsable accepté' }))
    expect(window.location.hash).toBe('#/')
    expect(isCounterMode('shop-1')).toBe(false)
    expect(getTillSession('shop-1')).toBeNull()
  })
})
