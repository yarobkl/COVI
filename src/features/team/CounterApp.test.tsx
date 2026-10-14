import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { clearCounterMode, enterCounterMode, isCounterMode } from '../../lib/counterMode'
import { supabase } from '../../lib/supabase'
import type { TillSession } from '../../lib/team'
import { clearTillSession, getTillSession, setTillSession } from '../../lib/tillSession'
import type { Shop } from '../../lib/types'
import { CounterGate } from './CounterGate'
import { INACTIVITY_MS } from './useInactivityLock'

vi.mock('../../lib/supabase', () => ({ supabase: { rpc: vi.fn() } }))
vi.mock('../sale/SalePage', () => ({
  SalePage: ({ seller }: { seller?: { name: string; tillToken?: string } }) => (
    <p>
      page:sale:{seller?.name}:{seller?.tillToken ? 'till' : 'none'}
    </p>
  ),
}))
vi.mock('../history/HistoryPage', () => ({
  HistoryPage: ({ sellerId }: { sellerId?: string }) => <p>page:history:{sellerId ?? 'all'}</p>,
}))
vi.mock('../sync/NetStatus', () => ({ NetStatus: () => null }))
vi.mock('../sync/useSyncState', () => ({ useSyncState: () => ({ pending: 0 }) }))
const rpc = vi.mocked(supabase.rpc)

const shop: Shop = {
  id: 'shop-1',
  name: 'Chez Mama Grâce',
  city: 'Brazzaville',
  country: 'République du Congo',
  currency: 'XAF',
}
const TOKEN = 'c'.repeat(64)
const awa: TillSession = {
  shopId: 'shop-1',
  memberId: 'm-awa',
  displayName: 'Awa',
  maxDiscountPct: 10,
  token: TOKEN,
  expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  sellerId: 'u-awa',
  canViewShopSales: false,
}

/** The owner's full application, as rendered by App (navigation to every owner page). */
const OwnerApp = () => (
  <nav aria-label="Sommaire">
    {['Stock', 'Arrivages', 'Ventes', 'Charges', 'Bilan', 'Ma boutique', 'Équipe'].map((p) => (
      <a key={p} href={`#/${p}`}>
        {p}
      </a>
    ))}
  </nav>
)

const signOut = vi.fn().mockResolvedValue(undefined)
const renderGate = () =>
  render(
    <CounterGate shop={shop} signOut={signOut}>
      <OwnerApp />
    </CounterGate>,
  )

function answer(leave: unknown, unlock: unknown = { status: 'ok' }) {
  rpc.mockImplementation(((name: string) => {
    if (name === 'leave_counter_mode') return Promise.resolve({ data: leave, error: null })
    if (name === 'unlock_till_session') return Promise.resolve({ data: unlock, error: null })
    if (name === 'list_shop_members') return Promise.resolve({ data: [], error: null })
    return Promise.resolve({ data: null, error: { message: 'unexpected ' + name } })
  }) as never)
}

const type = (pin: string) => {
  for (const d of pin) fireEvent.click(screen.getByRole('button', { name: d }))
}

async function askToLeave(pin: string) {
  fireEvent.click(screen.getByRole('button', { name: 'Revenir au responsable' }))
  type(pin)
  await act(async () => {
    fireEvent.click(screen.getByRole('button', { name: 'Revenir au responsable' }))
  })
}

beforeEach(() => {
  localStorage.clear()
  sessionStorage.clear()
  clearTillSession()
  clearCounterMode()
})
afterEach(() => {
  cleanup()
  rpc.mockReset()
  vi.useRealTimers()
})

describe('Counter mode (owner’s shared device)', () => {
  it('without counter mode, the owner’s app is shown', () => {
    renderGate()
    expect(screen.getByRole('link', { name: 'Bilan' })).toBeTruthy()
  })

  it('hides every owner page: only Vendre and the cashier’s sales', () => {
    setTillSession(awa)
    enterCounterMode('shop-1')
    renderGate()
    for (const page of ['Stock', 'Arrivages', 'Charges', 'Bilan', 'Ma boutique', 'Équipe'])
      expect(screen.queryByRole('link', { name: page })).toBeNull()
    expect(screen.queryByRole('navigation', { name: 'Sommaire' })).toBeNull()
    expect(screen.getByText('page:sale:Awa:till')).toBeTruthy()
    expect(screen.getByText('Awa')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Ses ventes' }))
    // Default (can_view_shop_sales = false): only her own sales.
    expect(screen.getByText('page:history:u-awa')).toBeTruthy()
  })

  it('a till session alone (older version, no flag) is counter mode too', () => {
    setTillSession(awa)
    renderGate()
    expect(screen.queryByRole('link', { name: 'Bilan' })).toBeNull()
    expect(isCounterMode('shop-1')).toBe(true)
  })

  it('stays in counter mode after a reload, even when the till token is gone', () => {
    enterCounterMode('shop-1')
    answer({ status: 'ok' })
    renderGate()
    expect(screen.queryByRole('link', { name: 'Bilan' })).toBeNull()
    expect(screen.getByText('Qui tient la caisse ?')).toBeTruthy()
  })

  it('leaving asks the owner’s code, checked by the server, then gives the app back', async () => {
    setTillSession(awa)
    enterCounterMode('shop-1')
    answer({ status: 'ok' })
    renderGate()
    await askToLeave('7391')
    expect(rpc).toHaveBeenCalledWith('leave_counter_mode', {
      p_shop_id: 'shop-1',
      p_pin: '7391',
      p_token: TOKEN,
    })
    expect(screen.getByRole('link', { name: 'Bilan' })).toBeTruthy()
    expect(getTillSession('shop-1')).toBeNull()
    expect(isCounterMode('shop-1')).toBe(false)
  })

  it('a wrong owner code keeps the counter closed and says how many tries are left', async () => {
    setTillSession(awa)
    enterCounterMode('shop-1')
    answer({ status: 'invalid', attempts_left: 3 })
    renderGate()
    await askToLeave('1590')
    expect(screen.getByText('Code du responsable incorrect. Encore 3 essais.')).toBeTruthy()
    expect(screen.queryByRole('link', { name: 'Bilan' })).toBeNull()
    expect(isCounterMode('shop-1')).toBe(true)
    expect(getTillSession('shop-1')?.token).toBe(TOKEN)
  })

  it('says when the owner’s code is locked after too many tries', async () => {
    setTillSession(awa)
    enterCounterMode('shop-1')
    answer({ status: 'locked', retry_after: '2026-10-14T10:15:00Z' })
    renderGate()
    await askToLeave('1590')
    expect(
      screen.getByText('Trop d’essais. Le code du responsable est bloqué 15 minutes.'),
    ).toBeTruthy()
    expect(screen.queryByRole('link', { name: 'Bilan' })).toBeNull()
  })

  it('« Rester au comptoir » goes back to the till', () => {
    setTillSession(awa)
    enterCounterMode('shop-1')
    renderGate()
    fireEvent.click(screen.getByRole('button', { name: 'Revenir au responsable' }))
    fireEvent.click(screen.getByRole('button', { name: 'Rester au comptoir' }))
    expect(screen.getByText('page:sale:Awa:till')).toBeTruthy()
  })

  it('locks after 5 minutes without activity; the cashier’s PIN reopens it', async () => {
    vi.useFakeTimers()
    setTillSession(awa)
    enterCounterMode('shop-1')
    answer({ status: 'ok' }, { status: 'invalid', attempts_left: 4 })
    renderGate()
    act(() => {
      vi.advanceTimersByTime(INACTIVITY_MS + 10)
    })
    expect(screen.getByText('Caisse de Awa verrouillée')).toBeTruthy()
    expect(screen.queryByText('page:sale:Awa:till')).toBeNull()
    type('1111')
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Reprendre la caisse' }))
    })
    expect(rpc).toHaveBeenCalledWith('unlock_till_session', {
      p_shop_id: 'shop-1',
      p_token: TOKEN,
      p_pin: '1111',
    })
    expect(screen.getByText('Code PIN incorrect. Encore 4 essais.')).toBeTruthy()
    answer({ status: 'ok' }, { status: 'ok' })
    type('4826')
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Reprendre la caisse' }))
    })
    expect(screen.getByText('page:sale:Awa:till')).toBeTruthy()
  })

  it('from the lock, « Changer de caissier » then « Annuler » stays locked', () => {
    vi.useFakeTimers()
    setTillSession(awa)
    enterCounterMode('shop-1')
    answer({ status: 'ok' })
    renderGate()
    act(() => {
      vi.advanceTimersByTime(INACTIVITY_MS + 10)
    })
    fireEvent.click(screen.getByRole('button', { name: 'Changer de caissier' }))
    expect(screen.getByText('Qui tient la caisse ?')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Annuler' }))
    expect(screen.getByText('Caisse de Awa verrouillée')).toBeTruthy()
  })

  it('a cashier allowed to see every sale gets all of them', () => {
    setTillSession({ ...awa, canViewShopSales: true })
    enterCounterMode('shop-1')
    renderGate()
    fireEvent.click(screen.getByRole('button', { name: 'Ventes' }))
    expect(screen.getByText('page:history:all')).toBeTruthy()
  })
})
