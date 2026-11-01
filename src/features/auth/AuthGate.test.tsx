import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '../../lib/supabase'
import { AuthGate } from './AuthGate'

const chain = {
  select: vi.fn(),
  eq: vi.fn(),
  limit: vi.fn(),
  maybeSingle: vi.fn(),
}
vi.mock('../../lib/supabase', () => ({
  supabase: {
    auth: {
      getSession: vi.fn(),
      onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: () => {} } } })),
      signOut: vi.fn(),
    },
    from: vi.fn(),
    rpc: vi.fn(),
  },
}))
vi.mock('../../lib/desktopAuth', () => ({ listenForDesktopOAuth: () => Promise.resolve(() => {}) }))
vi.mock('./CreateShopForm', () => ({
  CreateShopForm: ({ onJoin }: { onJoin?: () => void }) => (
    <button type="button" onClick={onJoin}>
      create-shop:J’ai un code de caissier
    </button>
  ),
}))
vi.mock('../salon/SalonStaffApp', () => ({
  SalonStaffApp: ({ space }: { space: { shop_name: string; role: string } }) => (
    <p>
      salon-staff:{space.shop_name}:{space.role}
    </p>
  ),
}))
vi.mock('../team/CashierApp', () => ({
  CashierApp: ({ membership }: { membership: { shop_name: string; display_name: string } }) => (
    <p>
      cashier:{membership.shop_name}:{membership.display_name}
    </p>
  ),
}))

const ownShop = { id: 'shop-own', name: 'Ma Boutique', city: null, country: null, currency: 'XAF' }
const membership = {
  member_id: 'm-1',
  shop_id: 'shop-other',
  shop_name: 'Chez Mama Grâce',
  shop_city: null,
  shop_country: null,
  shop_currency: 'XAF',
  display_name: 'Awa',
  role: 'cashier',
  can_view_shop_sales: false,
  max_discount_pct: 10,
  pin_set: true,
  pin_must_change: false,
}

const salonSpace = {
  shop_id: 'salon-1',
  shop_name: 'Salon Beauté Divine',
  role: 'stylist',
  display_name: 'Paul',
  employee_id: 'emp-1',
}

function serve({
  shop,
  members,
  membersFail = false,
  salons = [],
}: {
  shop: typeof ownShop | null
  members: (typeof membership)[]
  membersFail?: boolean
  salons?: (typeof salonSpace)[]
}) {
  vi.mocked(supabase.auth.getSession).mockResolvedValue({
    data: { session: { user: { id: 'user-1' } } },
    error: null,
  } as never)
  chain.select.mockReturnValue(chain)
  chain.eq.mockReturnValue(chain)
  chain.limit.mockReturnValue(chain)
  chain.maybeSingle.mockResolvedValue({ data: shop, error: null })
  vi.mocked(supabase.from).mockReturnValue(chain as never)
  vi.mocked(supabase.rpc).mockImplementation(((name: string) =>
    name === 'my_member_shops'
      ? Promise.resolve(
          membersFail
            ? { data: null, error: { message: 'Could not find the function' } }
            : { data: members, error: null },
        )
      : name === 'salon_staff_my_spaces'
        ? Promise.resolve({ data: salons, error: null })
        : Promise.resolve({ data: null, error: null })) as never)
}

async function renderGate() {
  await act(async () => {
    render(<AuthGate onSimulation={vi.fn()}>{(shop) => <p>owner-app:{shop.name}</p>}</AuthGate>)
  })
}

beforeEach(() => sessionStorage.clear())
afterEach(() => {
  cleanup()
  vi.clearAllMocks()
})

describe('AuthGate with cashiers', () => {
  it('owner only: opens the owner app as before, reading only the owned shop', async () => {
    serve({ shop: ownShop, members: [] })
    await renderGate()
    expect(screen.getByText('owner-app:Ma Boutique')).toBeTruthy()
    expect(chain.eq).toHaveBeenCalledWith('owner_id', 'user-1')
  })

  it('owner flow unchanged when the team functions are missing on the server', async () => {
    serve({ shop: ownShop, members: [], membersFail: true })
    await renderGate()
    expect(screen.getByText('owner-app:Ma Boutique')).toBeTruthy()
  })

  it('cashier only: opens the cashier space', async () => {
    serve({ shop: null, members: [membership] })
    await renderGate()
    expect(screen.getByText('cashier:Chez Mama Grâce:Awa')).toBeTruthy()
    expect(screen.queryByText(/owner-app/)).toBeNull()
  })

  it('owner and cashier: asks which space to open', async () => {
    serve({ shop: ownShop, members: [membership] })
    await renderGate()
    expect(screen.getByRole('heading', { name: 'Où travaillez-vous aujourd’hui ?' })).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Caisse de Chez Mama Grâce' }))
    expect(screen.getByText('cashier:Chez Mama Grâce:Awa')).toBeTruthy()
  })

  it('owner and cashier: can still open their own shop', async () => {
    serve({ shop: ownShop, members: [membership] })
    await renderGate()
    fireEvent.click(screen.getByRole('button', { name: 'Ma Boutique · responsable' }))
    expect(screen.getByText('owner-app:Ma Boutique')).toBeTruthy()
  })

  it('neither: create a shop, or join one with a code', async () => {
    serve({ shop: null, members: [] })
    await renderGate()
    fireEvent.click(screen.getByRole('button', { name: /J’ai un code de caissier/ }))
    expect(screen.getByRole('heading', { name: 'Rejoindre une boutique' })).toBeTruthy()
  })

  it('salon collaborator only: opens the salon space with their role', async () => {
    serve({ shop: null, members: [], salons: [salonSpace] })
    await renderGate()
    expect(screen.getByText('salon-staff:Salon Beauté Divine:stylist')).toBeTruthy()
    expect(screen.queryByText(/owner-app/)).toBeNull()
  })

  it('owner who also works in a salon: chooses the space', async () => {
    serve({ shop: ownShop, members: [], salons: [salonSpace] })
    await renderGate()
    fireEvent.click(screen.getByRole('button', { name: 'Salon Beauté Divine · Coiffeur' }))
    expect(screen.getByText('salon-staff:Salon Beauté Divine:stylist')).toBeTruthy()
  })

  it('owner flow unchanged when the salon functions are missing on the server', async () => {
    serve({ shop: ownShop, members: [] })
    vi.mocked(supabase.rpc).mockImplementation(((name: string) =>
      name === 'salon_staff_my_spaces'
        ? Promise.resolve({ data: null, error: { message: 'Could not find the function' } })
        : Promise.resolve({ data: [], error: null })) as never)
    await renderGate()
    expect(screen.getByText('owner-app:Ma Boutique')).toBeTruthy()
  })
})
