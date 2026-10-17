import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '../../lib/supabase'
import type { MemberShop } from '../../lib/team'
import { CashierApp, INACTIVITY_MS } from './CashierApp'

vi.mock('../../lib/supabase', () => ({ supabase: { rpc: vi.fn() } }))
vi.mock('../sale/SalePage', () => ({
  SalePage: ({ shopId, seller }: { shopId: string; seller?: { maxDiscountPct: number } }) => (
    <p>
      page:sale:{shopId}:max={seller?.maxDiscountPct}
    </p>
  ),
}))
vi.mock('../history/HistoryPage', () => ({
  HistoryPage: ({ mine }: { mine?: boolean }) => <p>page:history:{mine ? 'mine' : 'all'}</p>,
}))
vi.mock('../sync/NetStatus', () => ({ NetStatus: () => null }))
vi.mock('../sync/useSyncState', () => ({ useSyncState: () => ({ pending: 0 }) }))
const rpc = vi.mocked(supabase.rpc)

const membership: MemberShop = {
  member_id: 'm-1',
  shop_id: 'shop-1',
  shop_name: 'Chez Mama Grâce',
  shop_city: 'Brazzaville',
  shop_country: 'République du Congo',
  shop_currency: 'XAF',
  display_name: 'Awa',
  role: 'cashier',
  can_view_shop_sales: false,
  max_discount_pct: 10,
  pin_set: true,
  pin_must_change: false,
}

afterEach(() => {
  cleanup()
  rpc.mockReset()
  vi.useRealTimers()
})

async function unlock() {
  rpc.mockResolvedValue({ data: { status: 'ok' }, error: null } as never)
  for (const d of '4826') fireEvent.click(screen.getByRole('button', { name: d }))
  await act(async () => {
    fireEvent.click(screen.getByRole('button', { name: 'Ouvrir la caisse' }))
  })
}

const renderApp = (m: Partial<MemberShop> = {}) =>
  render(
    <CashierApp
      userId="u-awa"
      membership={{ ...membership, ...m }}
      signOut={vi.fn().mockResolvedValue(undefined)}
      onLostAccess={vi.fn()}
    />,
  )

describe('CashierApp (cashier on their own account)', () => {
  it('opens locked behind the PIN', () => {
    renderApp()
    expect(screen.getByRole('heading', { name: 'Bonjour Awa' })).toBeTruthy()
    expect(screen.queryByText(/page:sale/)).toBeNull()
  })

  it('offers Vendre and « Mes ventes » only, with the cashier’s discount', async () => {
    renderApp()
    await unlock()
    expect(screen.getByText('page:sale:shop-1:max=10')).toBeTruthy()
    const tabs = screen.getAllByRole('button').map((b) => b.textContent)
    expect(tabs).toContain('Vendre')
    expect(tabs).toContain('Mes ventes')
    for (const owner of ['Stock', 'Arrivages', 'Charges', 'Bilan', 'Ma boutique', 'Accueil'])
      expect(screen.queryByText(owner)).toBeNull()
    fireEvent.click(screen.getByRole('button', { name: 'Mes ventes' }))
    expect(screen.getByText('page:history:mine')).toBeTruthy()
  })

  it('asks to choose a PIN first when none is set', () => {
    renderApp({ pin_set: false })
    expect(screen.getByRole('heading', { name: 'Choisissez votre code PIN' })).toBeTruthy()
  })

  it('explains a reset by the owner', () => {
    renderApp({ pin_set: false, pin_must_change: true })
    expect(screen.getByText(/Le responsable a effacé votre ancien code/)).toBeTruthy()
  })

  it('locks itself after 5 minutes without activity, not before', async () => {
    vi.useFakeTimers()
    renderApp()
    await unlock()
    act(() => {
      vi.advanceTimersByTime(INACTIVITY_MS - 60_000)
    })
    // Activity (a touch) restarts the countdown.
    fireEvent.pointerDown(window)
    act(() => {
      vi.advanceTimersByTime(INACTIVITY_MS - 1000)
    })
    expect(screen.queryByRole('heading', { name: 'Bonjour Awa' })).toBeNull()
    act(() => {
      vi.advanceTimersByTime(1000)
    })
    expect(screen.getByRole('heading', { name: 'Bonjour Awa' })).toBeTruthy()
  })

  it('« Verrouiller » locks at once', async () => {
    renderApp()
    await unlock()
    fireEvent.click(screen.getByRole('button', { name: 'Verrouiller' }))
    expect(screen.getByRole('heading', { name: 'Bonjour Awa' })).toBeTruthy()
  })
})
