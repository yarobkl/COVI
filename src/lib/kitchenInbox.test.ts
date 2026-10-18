import { describe, expect, it } from 'vitest'
import { isKitchenCursor, newlyArrivedKitchenCount, readKitchenInbox } from './kitchenInbox'
const event = (id: string, item = 'Poisson') => ({
  id,
  table: '4',
  item,
  orderReference: 'CMD-000001',
  quantity: 2,
  at: '2026-10-17T19:00:00Z',
})
describe('Kitchen durable inbox', () => {
  it('validates a monotonic signed-in-only payload with no private or financial fields', () => {
    const x = readKitchenInbox({
      events: [{ ...event('2'), customerPhone: 'SECRET', unitPriceXaf: 9000 }],
      more: false,
      lastSeenId: '1',
    })
    expect(x.events[0]).toEqual(event('2'))
    expect(JSON.stringify(x)).not.toContain('SECRET')
    expect(JSON.stringify(x)).not.toContain('9000')
  })
  it('rejects duplicates, backwards ids, truncated data and unsafe amounts', () => {
    expect(() =>
      readKitchenInbox({ events: [event('2'), event('2')], more: false, lastSeenId: '1' }),
    ).toThrow()
    expect(() => readKitchenInbox({ events: [event('1')], more: false, lastSeenId: '2' })).toThrow()
    expect(() => readKitchenInbox({ events: [], more: null, lastSeenId: '1' })).toThrow()
    expect(() =>
      readKitchenInbox({ events: [{ ...event('3'), quantity: 0 }], more: false, lastSeenId: '1' }),
    ).toThrow()
  })
  it('keeps event ids exact beyond JavaScript safe integers', () => {
    expect(isKitchenCursor('9007199254740993')).toBe(true)
    expect(isKitchenCursor('9223372036854775808')).toBe(false)
    const q = readKitchenInbox({
      events: [event('9007199254740993')],
      more: false,
      lastSeenId: '9007199254740992',
    })
    expect(q.events[0].id).toBe('9007199254740993')
  })
  it('does not pop notifications for the initial backlog or each refresh', () => {
    const a = readKitchenInbox({ events: [event('2')], more: false, lastSeenId: '0' })
    expect(newlyArrivedKitchenCount(null, a)).toEqual({ newest: '2', count: 0 })
    expect(newlyArrivedKitchenCount('2', a)).toEqual({ newest: '2', count: 0 })
    const b = readKitchenInbox({ events: [event('2'), event('3')], more: false, lastSeenId: '0' })
    expect(newlyArrivedKitchenCount('2', b)).toEqual({ newest: '3', count: 1 })
  })
  it('acknowledging a page preserves undisplayed events', () => {
    const page = readKitchenInbox({ events: [event('3'), event('4')], more: true, lastSeenId: '2' })
    expect(page.events[page.events.length - 1]?.id).toBe('4')
    expect(page.more).toBe(true)
  })
})
