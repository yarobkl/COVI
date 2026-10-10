import { act, renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { pageIds, parseHash, routeHash, routeKey } from './routes'
import { useHashRoute } from './useHashRoute'

describe('parseHash / routeHash', () => {
  it('opens Accueil for an empty or unknown hash', () => {
    expect(parseHash('')).toEqual({ page: 'accueil' })
    expect(parseHash('#/')).toEqual({ page: 'accueil' })
    expect(parseHash('#/nimporte-quoi')).toEqual({ page: 'accueil' })
    expect(parseHash('#access_token=abc')).toEqual({ page: 'accueil' })
  })

  it('reads every page and the arrival filters', () => {
    expect(parseHash('#/vendre')).toEqual({ page: 'vendre' })
    expect(parseHash('#vendre')).toEqual({ page: 'vendre' })
    expect(parseHash('#/arrivages/ballons')).toEqual({ page: 'arrivages', filter: 'ballons' })
    expect(parseHash('#/arrivages/commandes/')).toEqual({ page: 'arrivages', filter: 'commandes' })
    expect(parseHash('#/arrivages/autre')).toEqual({ page: 'arrivages' })
    expect(parseHash('#/stock/ballons')).toEqual({ page: 'stock' })
  })

  it('round-trips every route', () => {
    for (const page of pageIds) expect(parseHash(routeHash({ page }))).toEqual({ page })
    for (const filter of ['commandes', 'ballons'] as const)
      expect(parseHash(routeHash({ page: 'arrivages', filter }))).toEqual({
        page: 'arrivages',
        filter,
      })
    expect(routeHash({ page: 'accueil' })).toBe('#/')
  })

  it('gives each arrival filter its own key', () => {
    expect(routeKey({ page: 'accueil' })).toBe('accueil')
    expect(routeKey({ page: 'arrivages' })).toBe('arrivages')
    expect(routeKey({ page: 'arrivages', filter: 'ballons' })).toBe('arrivages/ballons')
  })
})

describe('useHashRoute', () => {
  afterEach(() => {
    window.location.hash = ''
  })

  it('follows the hash, including the back button', async () => {
    window.location.hash = '#/stock'
    const { result } = renderHook(() => useHashRoute())
    expect(result.current.route).toEqual({ page: 'stock' })
    act(() => result.current.navigate({ page: 'vendre' }))
    await act(async () => {
      await new Promise((r) => setTimeout(r, 0))
    })
    expect(window.location.hash).toBe('#/vendre')
    expect(result.current.route).toEqual({ page: 'vendre' })
    await act(async () => {
      window.history.back()
      await new Promise((r) => setTimeout(r, 20))
    })
    expect(result.current.route).toEqual({ page: 'stock' })
  })
})
