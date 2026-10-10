import { afterEach, describe, expect, it, vi } from 'vitest'
import {
  clock,
  localDay,
  localMonth,
  longDay,
  monthName,
  shortDay,
  ticketClock,
  ticketDay,
  whenLabel,
} from './dates'

describe('spoken dates', () => {
  it('writes days and times the French way', () => {
    const d = new Date(2026, 9, 8, 14, 32)
    expect(longDay(d)).toBe('Jeudi 8 octobre')
    expect(monthName(d)).toBe('octobre')
    expect(shortDay(new Date(2026, 9, 2))).toBe('2 oct.')
    expect(clock(new Date(2026, 9, 8, 9, 5))).toBe('9 h 05')
    expect(ticketClock(new Date(2026, 9, 8, 9, 5))).toBe('09:05')
    expect(ticketDay(d)).toBe('08/10')
  })

  it('says today and yesterday', () => {
    const now = new Date(2026, 9, 8, 18, 0)
    expect(whenLabel(new Date(2026, 9, 8, 14, 32), now)).toBe('aujourd’hui 14 h 32')
    expect(whenLabel(new Date(2026, 9, 7, 18, 5), now)).toBe('hier 18 h 05')
    expect(whenLabel(new Date(2026, 9, 2, 11, 48), now)).toBe('2 oct. 11 h 48')
    expect(whenLabel(new Date(2026, 8, 30, 23, 0), new Date(2026, 9, 1, 8, 0))).toBe('hier 23 h 00')
  })
})

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
