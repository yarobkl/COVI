import { afterEach, describe, expect, it, vi } from 'vitest'
import { localDay, localMonth } from './dates'

describe('localMonth', () => {
  it('formats the local year and zero-padded month', () => {
    expect(localMonth(new Date(2026, 0, 15))).toBe('2026-01')
    expect(localMonth(new Date(2026, 11, 1))).toBe('2026-12')
  })

  it('uses local time, not UTC, around midnight', () => {
    // 1 March 00:30 local time is still February in UTC for time zones east of Greenwich.
    expect(localMonth(new Date(2026, 2, 1, 0, 30))).toBe('2026-03')
    expect(localMonth(new Date(2026, 1, 28, 23, 59))).toBe('2026-02')
  })
})

describe('localDay', () => {
  afterEach(() => {
    vi.useRealTimers()
  })

  it('formats the local date with zero padding', () => {
    expect(localDay(new Date(2026, 4, 7))).toBe('2026-05-07')
    expect(localDay(new Date(2026, 9, 31, 23, 59, 59))).toBe('2026-10-31')
  })

  it('defaults to the current date', () => {
    vi.useFakeTimers()
    vi.setSystemTime(new Date(2026, 9, 9, 8, 0))
    expect(localDay()).toBe('2026-10-09')
    expect(localMonth()).toBe('2026-10')
  })
})
