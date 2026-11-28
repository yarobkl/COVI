import { act, renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { useSalonToday } from './useSalonLoad'

afterEach(() => {
  vi.useRealTimers()
})

describe('jour courant du salon', () => {
  it('suit le fuseau réglé, pas celui de l’appareil', () => {
    vi.useFakeTimers()
    // 23 h 30 UTC : déjà le 24 à Brazzaville (UTC+1), encore le 23 à Abidjan (UTC+0).
    vi.setSystemTime(new Date('2026-10-23T23:30:00Z'))
    expect(renderHook(() => useSalonToday('Africa/Brazzaville')).result.current).toBe('2026-10-24')
    expect(renderHook(() => useSalonToday('Africa/Abidjan')).result.current).toBe('2026-10-23')
  })

  it('passe au jour suivant à minuit quand la page reste ouverte', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date('2026-10-23T22:59:30Z')) // 23:59:30 à Brazzaville
    const { result } = renderHook(() => useSalonToday('Africa/Brazzaville'))
    expect(result.current).toBe('2026-10-23')
    act(() => {
      vi.advanceTimersByTime(60000)
    })
    expect(result.current).toBe('2026-10-24')
  })
})
