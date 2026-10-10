import { describe, expect, it } from 'vitest'
import {
  accessFromState,
  addShopBlockedReason,
  isSubscriptionInactive,
  OPEN_ACCESS,
  subscriptionAccess,
  type SubscriptionRow,
  type SubscriptionState,
} from './subscription'

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
    expect(subscriptionAccess(false, [], now)).toMatchObject({
      readOnly: false,
      shopLimit: 1,
      addLimit: 1,
    })
  })
  it('active within its period: writable, with its quota', () => {
    expect(subscriptionAccess(true, [row({})], now)).toMatchObject({
      readOnly: false,
      shopLimit: 2,
      addLimit: 2,
      status: 'active',
    })
  })
  it('first invoice never paid: writable', () => {
    const r = row({ status: 'pending_payment', period_start: null, period_end: null })
    expect(subscriptionAccess(true, [r], now).readOnly).toBe(false)
  })
  it('suspended: read only', () => {
    expect(subscriptionAccess(true, [row({ status: 'suspended' })], now)).toMatchObject({
      readOnly: true,
      shopLimit: 2,
      addLimit: 0,
      status: 'suspended',
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
    expect(subscriptionAccess(true, [], now)).toMatchObject({
      readOnly: true,
      shopLimit: null,
      addLimit: 0,
    })
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

describe('covi_my_subscription_state() → interface', () => {
  const state = (over: Partial<SubscriptionState>): SubscriptionState => ({
    status: 'active',
    writable: true,
    shopLimit: 2,
    shopCount: 1,
    canAddShop: true,
    periodEnd: '2099-01-01T00:00:00Z',
    isLegacyV1: false,
    ...over,
  })

  it('active with room: writable, adding open up to the quota', () => {
    const access = accessFromState(state({}))
    expect(access).toEqual({
      readOnly: false,
      shopLimit: 2,
      addLimit: 2,
      canAddShop: true,
      status: 'active',
    })
    expect(addShopBlockedReason(access, 1)).toBeNull()
    // Once the 2nd shop exists (before the state is read again): closed.
    expect(addShopBlockedReason(access, 2)).toBe(
      'Votre abonnement couvre 2 boutiques. Pour en ajouter une, contactez COVI.',
    )
  })
  it('quota reached', () => {
    expect(
      addShopBlockedReason(accessFromState(state({ shopCount: 2, canAddShop: false })), 2),
    ).toBe('Votre abonnement couvre 2 boutiques. Pour en ajouter une, contactez COVI.')
  })
  it('suspended', () => {
    const access = accessFromState(
      state({ status: 'suspended', writable: false, canAddShop: false }),
    )
    expect(access.readOnly).toBe(true)
    expect(addShopBlockedReason(access, 1)).toBe(
      'Votre abonnement est suspendu. Contactez COVI pour le renouveler.',
    )
  })
  it('past its period, grace or unpaid: not active', () => {
    for (const s of [
      state({ writable: false, canAddShop: false }),
      state({ status: 'grace', canAddShop: false }),
      state({ status: 'pending_payment', canAddShop: false }),
    ])
      expect(addShopBlockedReason(accessFromState(s), 1)).toBe(
        'Votre abonnement n’est pas actif. Contactez COVI pour le renouveler.',
      )
  })
  it('V1 owner: one shop', () => {
    const v1 = state({ status: null, shopLimit: 1, isLegacyV1: true })
    expect(addShopBlockedReason(accessFromState({ ...v1, shopCount: 0 }), 0)).toBeNull()
    expect(addShopBlockedReason(accessFromState({ ...v1, canAddShop: false }), 1)).toBe(
      'Votre abonnement couvre 1 boutique. Pour en ajouter une, contactez COVI.',
    )
  })
  it('unknown state: nothing blocked, the server decides', () => {
    expect(addShopBlockedReason(OPEN_ACCESS, 5)).toBeNull()
  })
})
