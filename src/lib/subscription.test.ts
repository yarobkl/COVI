import { describe, expect, it } from 'vitest'
import { isSubscriptionInactive, subscriptionAccess, type SubscriptionRow } from './subscription'

const now = new Date('2026-10-10T12:00:00Z')
const row = (over: Partial<SubscriptionRow>): SubscriptionRow => ({
  status: 'active',
  shop_limit: 2,
  period_start: '2026-10-01T00:00:00Z',
  period_end: '2026-11-01T00:00:00Z',
  grace_until: null,
  ...over,
})

describe('subscriptionAccess (same rule as covi_shop_subscription_writable)', () => {
  it('V1 owner without SaaS account: writable, 1 shop', () => {
    expect(subscriptionAccess(false, [], now)).toEqual({ readOnly: false, shopLimit: 1 })
  })
  it('active within its period: writable, with its quota', () => {
    expect(subscriptionAccess(true, [row({})], now)).toEqual({ readOnly: false, shopLimit: 2 })
  })
  it('first invoice never paid: writable', () => {
    const r = row({ status: 'pending_payment', period_start: null, period_end: null })
    expect(subscriptionAccess(true, [r], now).readOnly).toBe(false)
  })
  it('suspended: read only', () => {
    expect(subscriptionAccess(true, [row({ status: 'suspended' })], now)).toEqual({
      readOnly: true,
      shopLimit: 2,
    })
  })
  it('active but past its period: read only', () => {
    const r = row({ period_start: '2026-09-01T00:00:00Z', period_end: '2026-10-01T00:00:00Z' })
    expect(subscriptionAccess(true, [r], now).readOnly).toBe(true)
  })
  it('grace: writable before grace_until, read only after', () => {
    expect(
      subscriptionAccess(true, [row({ status: 'grace', grace_until: '2026-10-15T00:00:00Z' })], now)
        .readOnly,
    ).toBe(false)
    expect(
      subscriptionAccess(true, [row({ status: 'grace', grace_until: '2026-10-05T00:00:00Z' })], now)
        .readOnly,
    ).toBe(true)
  })
  it('only cancelled subscriptions (account without current one): read only', () => {
    expect(subscriptionAccess(true, [row({ status: 'cancelled' })], now).readOnly).toBe(true)
    expect(subscriptionAccess(true, [], now)).toEqual({ readOnly: true, shopLimit: null })
  })
})

describe('isSubscriptionInactive', () => {
  it('recognises the P0001 refusal of the write guard', () => {
    expect(
      isSubscriptionInactive({
        code: 'P0001',
        message: 'Subscription inactive: shop is read-only',
      }),
    ).toBe(true)
    expect(isSubscriptionInactive({ message: 'Insufficient stock' })).toBe(false)
    expect(isSubscriptionInactive(null)).toBe(false)
  })
})
