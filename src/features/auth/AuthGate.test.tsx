import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Shop } from '../../lib/types'

// A fake Supabase: each account only sees its own shops (as RLS does).
type Fake = {
  userId: string | null
  shopsByUser: Record<string, Shop[]>
  shopsFail: boolean
  account: { id: string } | null
  subs: unknown[]
  createShop: (args: Record<string, unknown>) => { data: Shop | null; error: unknown }
  authCallback: ((event: string, session: unknown) => void) | null
  shopRequests: number
}
const fake: Fake = {
  userId: 'u1',
  shopsByUser: {},
  shopsFail: false,
  account: null,
  subs: [],
  createShop: () => ({ data: null, error: null }),
  authCallback: null,
  shopRequests: 0,
}
const sessionOf = (id: string | null) => (id ? { user: { id } } : null)

function query(table: string) {
  const result = () => {
    if (table === 'shops') {
      fake.shopRequests++
      if (fake.shopsFail) return Promise.reject(new TypeError('Failed to fetch'))
      return Promise.resolve({ data: fake.shopsByUser[fake.userId ?? ''] ?? [], error: null })
    }
    if (table === 'covi_owner_accounts') return Promise.resolve({ data: fake.account, error: null })
    if (table === 'covi_subscriptions') return Promise.resolve({ data: fake.subs, error: null })
    return Promise.resolve({ data: null, error: { message: 'unknown table' } })
  }
  const builder = {
    select: () => builder,
    order: () => builder,
    eq: () => builder,
    limit: () => builder,
    maybeSingle: () => builder,
    then: (ok: (v: unknown) => unknown, ko?: (e: unknown) => unknown) => result().then(ok, ko),
  }
  return builder
}

vi.mock('../../lib/supabase', () => ({
  supabase: {
    from: (table: string) => query(table),
    rpc: (_name: string, args: Record<string, unknown>) => Promise.resolve(fake.createShop(args)),
    auth: {
      getSession: () => Promise.resolve({ data: { session: sessionOf(fake.userId) } }),
      onAuthStateChange: (cb: Fake['authCallback']) => {
        fake.authCallback = cb
        return { data: { subscription: { unsubscribe: () => {} } } }
      },
      signOut: () => Promise.resolve({ error: null }),
    },
  },
}))
vi.mock('../../lib/desktopAuth', () => ({
  listenForDesktopOAuth: () => Promise.resolve(() => {}),
}))

const { AuthGate } = await import('./AuthGate')
const { reportSubscriptionInactive } = await import('../../lib/subscription')
const { setSyncUser } = await import('../../lib/offline')

const shop = (id: string, name: string): Shop => ({
  id,
  name,
  city: 'Brazzaville',
  country: 'Congo',
  currency: 'XAF',
})
const A = shop('shop-a', 'Boutique A')
const B = shop('shop-b', 'Boutique B')
const C = shop('shop-c', 'Boutique C (autre compte)')

function renderGate() {
  return render(
    <AuthGate onSimulation={() => {}}>
      {(s, _signOut, _update, account) => (
        <div>
          <p>ouverte:{s.id}</p>
          <p>boutiques:{account.shopCount}</p>
          <p>lecture-seule:{String(account.readOnly)}</p>
          {account.switchShop && (
            <button type="button" onClick={account.switchShop}>
              Changer de boutique
            </button>
          )}
          {account.addShop && (
            <button type="button" onClick={account.addShop}>
              Ajouter une boutique
            </button>
          )}
        </div>
      )}
    </AuthGate>,
  )
}

beforeEach(() => {
  localStorage.clear()
  Object.assign(fake, {
    userId: 'u1',
    shopsByUser: { u1: [A, B], u2: [C] },
    shopsFail: false,
    account: null,
    subs: [],
    createShop: () => ({ data: null, error: null }),
    authCallback: null,
    shopRequests: 0,
  })
})
afterEach(cleanup)

describe('AuthGate: shops of the account', () => {
  it('0 shop: the creation form', async () => {
    fake.shopsByUser.u1 = []
    renderGate()
    expect(await screen.findByText('Comment s’appelle votre boutique ?')).toBeTruthy()
  })

  it('1 shop: opened directly, no switch offered', async () => {
    fake.shopsByUser.u1 = [A]
    renderGate()
    expect(await screen.findByText('ouverte:shop-a')).toBeTruthy()
    expect(screen.queryByRole('button', { name: 'Changer de boutique' })).toBeNull()
    expect(localStorage.getItem('covi:active-shop:u1')).toContain('shop-a')
  })

  it('2 shops: asks, remembers the choice, reopens it after a reload', async () => {
    const first = renderGate()
    expect(await screen.findByRole('heading', { name: 'Choisir une boutique' })).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: /Boutique B/ }))
    expect(await screen.findByText('ouverte:shop-b')).toBeTruthy()
    expect(screen.getByText('boutiques:2')).toBeTruthy()
    first.unmount()
    // Reload of the page: the same shop, without asking.
    renderGate()
    expect(await screen.findByText('ouverte:shop-b')).toBeTruthy()
  })

  it('switching shop goes back to the choice and opens the other one', async () => {
    localStorage.setItem('covi:active-shop:u1', JSON.stringify(A))
    renderGate()
    expect(await screen.findByText('ouverte:shop-a')).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Changer de boutique' }))
    const label = await screen.findByRole('button', { name: /Boutique A/ })
    expect(label.getAttribute('aria-current')).toBe('true')
    fireEvent.click(screen.getByRole('button', { name: /Boutique B/ }))
    expect(await screen.findByText('ouverte:shop-b')).toBeTruthy()
    expect(JSON.parse(localStorage.getItem('covi:active-shop:u1')!).id).toBe('shop-b')
  })

  it('a remembered shop that was deleted is not opened and the preference is dropped', async () => {
    localStorage.setItem(
      'covi:active-shop:u1',
      JSON.stringify(shop('shop-deleted', 'Boutique fermée')),
    )
    renderGate()
    expect(await screen.findByRole('heading', { name: 'Choisir une boutique' })).toBeTruthy()
    expect(screen.queryByText(/Boutique fermée/)).toBeNull()
    expect(localStorage.getItem('covi:active-shop:u1')).toBeNull()
  })

  it('another account on the same device never opens the first account’s shop', async () => {
    localStorage.setItem('covi:active-shop:u1', JSON.stringify(B))
    renderGate()
    expect(await screen.findByText('ouverte:shop-b')).toBeTruthy()
    // u2 signs in on the same phone (its own shops only, as RLS returns them).
    fake.userId = 'u2'
    act(() => fake.authCallback?.('SIGNED_IN', sessionOf('u2')))
    expect(await screen.findByText('ouverte:shop-c')).toBeTruthy()
    expect(screen.queryByText('ouverte:shop-b')).toBeNull()
    expect(localStorage.getItem('covi:active-shop:u2')).toContain('shop-c')
    expect(localStorage.getItem('covi:active-shop:u1')).toContain('shop-b')
  })

  it('a preference copied under another account’s key is not an authorization', async () => {
    // u2's preference points to u1's shop B (tampered or stale): B is not in u2's list.
    fake.userId = 'u2'
    fake.shopsByUser.u2 = [C, shop('shop-d', 'Boutique D')]
    localStorage.setItem('covi:active-shop:u2', JSON.stringify(B))
    renderGate()
    expect(await screen.findByRole('heading', { name: 'Choisir une boutique' })).toBeTruthy()
    expect(screen.queryByText(/Boutique B/)).toBeNull()
    expect(localStorage.getItem('covi:active-shop:u2')).toBeNull()
  })
})

describe('AuthGate: network cut while loading the shops', () => {
  it('keeps this account’s active shop from the device; never « create your shop »', async () => {
    localStorage.setItem('covi:active-shop:u1', JSON.stringify(B))
    fake.shopsFail = true
    renderGate()
    expect(await screen.findByText('ouverte:shop-b')).toBeTruthy()
    expect(screen.queryByText('Comment s’appelle votre boutique ?')).toBeNull()
    // The list is unknown: no switch, no add.
    expect(screen.queryByRole('button', { name: 'Changer de boutique' })).toBeNull()
    expect(screen.queryByRole('button', { name: 'Ajouter une boutique' })).toBeNull()
  })

  it('without a copy: an error screen with « Réessayer », then the shops', async () => {
    fake.shopsFail = true
    renderGate()
    expect(await screen.findByRole('heading', { name: 'Vos boutiques ne s’affichent pas' }))
    expect(screen.queryByText('Comment s’appelle votre boutique ?')).toBeNull()
    expect(screen.queryByText(/ouverte:/)).toBeNull()
    fake.shopsFail = false
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }))
    expect(await screen.findByRole('heading', { name: 'Choisir une boutique' })).toBeTruthy()
  })

  it('never opens the copy of another account', async () => {
    localStorage.setItem('covi:active-shop:u1', JSON.stringify(B))
    fake.userId = 'u2'
    fake.shopsFail = true
    renderGate()
    expect(await screen.findByRole('heading', { name: 'Vos boutiques ne s’affichent pas' }))
    expect(screen.queryByText('ouverte:shop-b')).toBeNull()
  })
})

describe('AuthGate: adding a shop', () => {
  it('within the quota: created and opened', async () => {
    fake.shopsByUser.u1 = [A]
    const created = shop('shop-new', 'Boutique Neuve')
    fake.createShop = (args) => {
      expect(args).toMatchObject({ p_name: 'Boutique Neuve', p_currency: 'XAF' })
      return { data: created, error: null }
    }
    renderGate()
    fireEvent.click(await screen.findByRole('button', { name: 'Ajouter une boutique' }))
    fireEvent.change(screen.getByLabelText('Nom de la boutique'), {
      target: { value: 'Boutique Neuve' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Créer cette boutique' }))
    expect(await screen.findByText('ouverte:shop-new')).toBeTruthy()
    expect(screen.getByText('boutiques:2')).toBeTruthy()
  })

  it('« Shop quota reached »: says how many shops the subscription covers', async () => {
    fake.account = { id: 'acc-1' }
    fake.subs = [
      {
        status: 'active',
        shop_limit: 2,
        period_start: '2020-01-01T00:00:00Z',
        period_end: '2999-01-01T00:00:00Z',
        grace_until: null,
      },
    ]
    fake.createShop = () => ({
      data: null,
      error: { code: 'P0001', message: 'Shop quota reached' },
    })
    localStorage.setItem('covi:active-shop:u1', JSON.stringify(A))
    renderGate()
    fireEvent.click(await screen.findByRole('button', { name: 'Ajouter une boutique' }))
    fireEvent.change(screen.getByLabelText('Nom de la boutique'), { target: { value: 'C' } })
    fireEvent.click(screen.getByRole('button', { name: 'Créer cette boutique' }))
    expect(
      await screen.findByText(
        'Votre abonnement couvre 2 boutiques. Pour en ajouter une, contactez COVI.',
      ),
    ).toBeTruthy()
    fireEvent.click(screen.getByRole('button', { name: 'Annuler' }))
    expect(await screen.findByText('ouverte:shop-a')).toBeTruthy()
  })

  it('V1 account (quota 1): the existing shop sent back is a refusal, not a new shop', async () => {
    fake.shopsByUser.u1 = [A]
    fake.createShop = () => ({ data: A, error: null })
    renderGate()
    fireEvent.click(await screen.findByRole('button', { name: 'Ajouter une boutique' }))
    fireEvent.change(screen.getByLabelText('Nom de la boutique'), { target: { value: 'Deux' } })
    fireEvent.click(screen.getByRole('button', { name: 'Créer cette boutique' }))
    expect(
      await screen.findByText(
        'Votre abonnement couvre 1 boutique. Pour en ajouter une, contactez COVI.',
      ),
    ).toBeTruthy()
  })

  it('« Active subscription required »', async () => {
    fake.shopsByUser.u1 = [A]
    fake.createShop = () => ({
      data: null,
      error: { code: '42501', message: 'Active subscription required' },
    })
    renderGate()
    fireEvent.click(await screen.findByRole('button', { name: 'Ajouter une boutique' }))
    fireEvent.change(screen.getByLabelText('Nom de la boutique'), { target: { value: 'Deux' } })
    fireEvent.click(screen.getByRole('button', { name: 'Créer cette boutique' }))
    expect(
      await screen.findByText(
        'Votre abonnement n’est pas actif : impossible d’ajouter une boutique. Contactez COVI pour le renouveler.',
      ),
    ).toBeTruthy()
  })
})

describe('AuthGate: subscription', () => {
  it('suspended subscription read by the owner: read only, and it stays so', async () => {
    fake.shopsByUser.u1 = [A]
    fake.account = { id: 'acc-1' }
    fake.subs = [
      {
        status: 'suspended',
        shop_limit: 1,
        period_start: '2026-09-01T00:00:00Z',
        period_end: '2026-10-01T00:00:00Z',
        grace_until: null,
      },
    ]
    renderGate()
    expect(await screen.findByText('lecture-seule:true')).toBeTruthy()
  })

  it('no readable subscription (database not migrated): open, until a P0001 refusal', async () => {
    fake.shopsByUser.u1 = [A]
    renderGate()
    expect(await screen.findByText('lecture-seule:false')).toBeTruthy()
    act(() => reportSubscriptionInactive())
    await waitFor(() => expect(screen.getByText('lecture-seule:true')).toBeTruthy())
  })

  it('an offline sale refused at its sync for the subscription: read only', async () => {
    fake.shopsByUser.u1 = [A]
    setSyncUser('u1')
    renderGate()
    expect(await screen.findByText('lecture-seule:false')).toBeTruthy()
    localStorage.setItem(
      'covi:rejected-sales:v2',
      JSON.stringify([
        {
          id: 'op-1',
          shopId: 'shop-a',
          productId: 'p1',
          quantity: 1,
          soldUnitPrice: 1000,
          paymentLabel: 'cash',
          createdAt: new Date().toISOString(),
          attempts: 0,
          userId: 'u1',
          reason: 'Subscription inactive: shop is read-only',
          rejectedAt: new Date(Date.now() + 1000).toISOString(),
        },
      ]),
    )
    act(() => {
      window.dispatchEvent(new Event('covi-sync'))
    })
    await waitFor(() => expect(screen.getByText('lecture-seule:true')).toBeTruthy())
  })
})
