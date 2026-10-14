import { beforeEach, describe, expect, it, vi } from 'vitest'
import type { TillSession } from './team'

const session = (over: Partial<TillSession> = {}): TillSession => ({
  shopId: 'shop-1',
  memberId: 'member-1',
  displayName: 'Awa',
  maxDiscountPct: 10,
  token: 'a'.repeat(64),
  expiresAt: new Date(Date.now() + 3600_000).toISOString(),
  ...over,
})

// Fresh module for each test: the store keeps the session in memory.
async function store() {
  vi.resetModules()
  return import('./tillSession')
}

beforeEach(() => {
  sessionStorage.clear()
  localStorage.clear()
})

describe('till session store (shared counter device)', () => {
  it('keeps the token in memory and sessionStorage, never in localStorage', async () => {
    const s = await store()
    s.setTillSession(session())
    expect(s.getTillSession('shop-1')?.displayName).toBe('Awa')
    expect(sessionStorage.getItem('covi:till-session:v1')).toContain('a'.repeat(64))
    expect(JSON.stringify({ ...localStorage })).not.toContain('a'.repeat(64))
    // A reload of the tab finds it again (sessionStorage).
    const again = await store()
    expect(again.getTillSession('shop-1')?.memberId).toBe('member-1')
  })
  it('is bound to its shop', async () => {
    const s = await store()
    s.setTillSession(session())
    expect(s.getTillSession('shop-2')).toBeNull()
  })
  it('forgets an expired session', async () => {
    const s = await store()
    s.setTillSession(session({ expiresAt: new Date(Date.now() - 1000).toISOString() }))
    expect(s.getTillSession('shop-1', Date.now(), false)).toBeNull()
    expect(sessionStorage.getItem('covi:till-session:v1')).not.toBeNull()
    expect(s.getTillSession('shop-1')).toBeNull()
    expect(sessionStorage.getItem('covi:till-session:v1')).toBeNull()
  })
  it('clears on close or sign-out and notifies the screens', async () => {
    const s = await store()
    const listener = vi.fn()
    const unsubscribe = s.subscribeTillSession(listener)
    s.setTillSession(session())
    s.clearTillSession()
    expect(listener).toHaveBeenCalledTimes(2)
    expect(s.peekTillSession()).toBeNull()
    expect(sessionStorage.getItem('covi:till-session:v1')).toBeNull()
    unsubscribe()
  })
})
