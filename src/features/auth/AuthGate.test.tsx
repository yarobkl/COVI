import { act, cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import type { Shop } from '../../lib/types'

// supabase-js is simulated: tests drive the auth events and the answer of the `shops` query.
type Listener = (event: string, session: unknown) => void
const auth = vi.hoisted(() => ({
  listeners: [] as Listener[],
  persisted: null as string | null,
  session: null as unknown,
  shopsAnswers: [] as { data: unknown; error: unknown }[],
  shopsCalls: 0,
}))
vi.mock('../../lib/supabase', () => ({
  persistedUserId: () => auth.persisted,
  forgetPersistedSession: () => {
    auth.persisted = null
  },
  supabase: {
    auth: {
      onAuthStateChange: (cb: Listener) => {
        auth.listeners.push(cb)
        return { data: { subscription: { unsubscribe: () => undefined } } }
      },
      getSession: async () => ({ data: { session: auth.session }, error: null }),
      signOut: async () => ({ error: null }),
    },
    from: () => {
      const q = {
        select: () => q,
        limit: () => q,
        maybeSingle: async () => {
          auth.shopsCalls++
          return auth.shopsAnswers.shift() ?? { data: null, error: { message: 'Failed to fetch' } }
        },
      }
      return q
    },
  },
}))
vi.mock('../../lib/desktopAuth', () => ({
  listenForDesktopOAuth: async () => () => undefined,
  isTauriApp: () => false,
  desktopAuthRedirect: () => 'covi://auth/callback',
  openOAuthInSystemBrowser: async () => undefined,
}))

const { AuthGate } = await import('./AuthGate')
const { rememberShop, cachedShop } = await import('../../lib/offline')

const shop: Shop = {
  id: 'shop-1',
  name: 'Boutique Élégance',
  city: 'Brazzaville',
  country: 'Congo',
  currency: 'XAF',
}
const session = (id = 'u1') => ({ access_token: 'jwt', user: { id } })
const online = (value: boolean) =>
  Object.defineProperty(navigator, 'onLine', { value, configurable: true })

/** Emits an auth event as supabase-js does, and lets AuthGate's deferred handler run. */
async function emit(event: string, value: unknown) {
  await act(async () => {
    for (const listener of auth.listeners) listener(event, value)
    await new Promise((r) => setTimeout(r, 0))
    await new Promise((r) => setTimeout(r, 0))
  })
}
function renderGate() {
  return render(<AuthGate onSimulation={() => undefined}>{(s) => <p>app:{s.name}</p>}</AuthGate>)
}

beforeEach(() => {
  localStorage.clear()
  auth.listeners = []
  auth.persisted = null
  auth.session = null
  auth.shopsAnswers = []
  auth.shopsCalls = 0
  online(true)
})
afterEach(cleanup)

describe('AuthGate offline start', () => {
  it('opens on the remembered shop with an expired session and no network', async () => {
    online(false)
    auth.persisted = 'u1'
    await rememberShop('u1', shop)
    renderGate()
    // Before supabase-js answers (it retries the token refresh for ~25 s offline).
    expect(screen.getByText('app:Boutique Élégance')).toBeTruthy()
    // supabase-js gives up the refresh: INITIAL_SESSION without session, but the session is kept.
    await emit('INITIAL_SESSION', null)
    expect(screen.getByText('app:Boutique Élégance')).toBeTruthy()
    expect(screen.queryByRole('heading', { name: 'Connexion' })).toBeNull()
    expect(auth.shopsCalls).toBe(0)
  })

  it('confirms the shop once the token is refreshed', async () => {
    online(false)
    auth.persisted = 'u1'
    await rememberShop('u1', shop)
    renderGate()
    await emit('INITIAL_SESSION', null)
    online(true)
    auth.shopsAnswers.push({ data: { ...shop, name: 'Nouveau nom' }, error: null })
    await emit('TOKEN_REFRESHED', session())
    expect(screen.getByText('app:Nouveau nom')).toBeTruthy()
    expect(cachedShop<Shop>('u1')?.name).toBe('Nouveau nom')
  })

  it('explains the first launch offline instead of showing the creation form', async () => {
    online(false)
    auth.persisted = 'u1'
    renderGate()
    await emit('INITIAL_SESSION', null)
    expect(screen.getByRole('alert').textContent).toMatch(/Pas de connexion/)
    expect(screen.getByText('Réessayer')).toBeTruthy()
    expect(screen.queryByRole('heading', { name: 'Comment s’appelle votre boutique ?' })).toBeNull()
  })

  it('shows the sign-in form when no session is persisted', async () => {
    renderGate()
    await emit('INITIAL_SESSION', null)
    expect(screen.getByRole('heading', { name: 'Connexion' })).toBeTruthy()
  })

  it('signs out on SIGNED_OUT even with a remembered shop', async () => {
    auth.persisted = 'u1'
    await rememberShop('u1', shop)
    renderGate()
    auth.persisted = null
    await emit('SIGNED_OUT', null)
    expect(screen.getByRole('heading', { name: 'Connexion' })).toBeTruthy()
  })
})

describe('AuthGate online shop loading', () => {
  it('shows an error with retry, never the creation form, when the shops query fails', async () => {
    auth.persisted = 'u1'
    auth.session = session()
    auth.shopsAnswers.push({ data: null, error: { message: 'Failed to fetch' } })
    renderGate()
    await emit('INITIAL_SESSION', session())
    expect(screen.getByRole('alert').textContent).toMatch(/Impossible de charger votre commerce/)
    expect(screen.queryByRole('heading', { name: 'Comment s’appelle votre boutique ?' })).toBeNull()

    auth.shopsAnswers.push({ data: shop, error: null })
    await act(async () => {
      fireEvent.click(screen.getByText('Réessayer'))
      await new Promise((r) => setTimeout(r, 0))
    })
    expect(screen.getByText('app:Boutique Élégance')).toBeTruthy()
    expect(cachedShop<Shop>('u1')?.id).toBe('shop-1')
  })

  it('keeps the remembered shop when the shops query fails', async () => {
    auth.persisted = 'u1'
    await rememberShop('u1', shop)
    auth.shopsAnswers.push({ data: null, error: { message: 'Failed to fetch' } })
    renderGate()
    await emit('INITIAL_SESSION', session())
    expect(screen.getByText('app:Boutique Élégance')).toBeTruthy()
  })

  it('keeps the remembered shop when the server answers an empty list', async () => {
    auth.persisted = 'u1'
    await rememberShop('u1', shop)
    auth.shopsAnswers.push({ data: null, error: null })
    renderGate()
    await emit('INITIAL_SESSION', session())
    expect(screen.getByText('app:Boutique Élégance')).toBeTruthy()
    expect(screen.queryByRole('heading', { name: 'Comment s’appelle votre boutique ?' })).toBeNull()
  })

  it('offers to create the shop only when the server confirms there is none', async () => {
    auth.persisted = 'u1'
    auth.shopsAnswers.push({ data: null, error: null })
    renderGate()
    await emit('INITIAL_SESSION', session())
    expect(screen.getByRole('heading', { name: 'Comment s’appelle votre boutique ?' })).toBeTruthy()
  })
})
