import { describe, expect, it } from 'vitest'
import {
  EXTRA_SHOP_MONTHLY_XAF,
  FIRST_SHOP_MONTHLY_XAF,
  monthlySubscriptionXaf,
  monthlyUpgradeDifferenceXaf,
} from './subscriptionPricing'

describe('tarification COVI SaaS', () => {
  it('inclut la première boutique à 10 000 FCFA', () => {
    expect(FIRST_SHOP_MONTHLY_XAF).toBe(10_000)
    expect(EXTRA_SHOP_MONTHLY_XAF).toBe(5_000)
    expect(monthlySubscriptionXaf(1)).toBe(10_000)
  })

  it.each([
    [2, 15_000],
    [3, 20_000],
    [5, 30_000],
    [10, 55_000],
  ])('calcule %i boutiques à %i FCFA', (shops, amount) => {
    expect(monthlySubscriptionXaf(shops)).toBe(amount)
  })

  it('calcule le supplément mensuel sans prorata', () => {
    expect(monthlyUpgradeDifferenceXaf(1, 3)).toBe(10_000)
    expect(monthlyUpgradeDifferenceXaf(2, 2)).toBe(0)
  })

  it.each([0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1])(
    'refuse un quota invalide : %s',
    (shops) => {
      expect(() => monthlySubscriptionXaf(shops)).toThrow(RangeError)
    },
  )

  it('refuse une réduction dans le calcul du supplément', () => {
    expect(() => monthlyUpgradeDifferenceXaf(3, 2)).toThrow(RangeError)
  })
})
