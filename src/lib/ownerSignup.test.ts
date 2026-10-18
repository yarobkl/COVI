import { describe, expect, it } from 'vitest'
import {
  createOwnerSignupDetails,
  isValidOwnerPhone,
  ownerOnboardingHints,
} from './ownerSignup'

describe('owner signup details', () => {
  it('normalizes the owner profile while keeping business sector as a hint only', () => {
    const data = createOwnerSignupDetails({
      firstName: '  Marie ',
      lastName: '  Balossa  ',
      phone: ' +242 06 123 45 67 ',
      businessKind: 'restaurant',
      businessName: ' Chez Mama ',
    })
    expect(data).toEqual({
      first_name: 'Marie',
      last_name: 'Balossa',
      full_name: 'Marie Balossa',
      phone_number: '+242061234567',
      business_kind: 'restaurant',
      business_name: 'Chez Mama',
    })
    expect(ownerOnboardingHints(data)).toMatchObject({
      businessKind: 'restaurant',
      businessName: 'Chez Mama',
      phone: '+242061234567',
    })
  })

  it('rejects invalid phone numbers and unsupported sectors', () => {
    expect(isValidOwnerPhone('061234567')).toBe(false)
    expect(isValidOwnerPhone('+242061234567')).toBe(true)
    expect(() =>
      createOwnerSignupDetails({
        firstName: 'Awa',
        lastName: 'Yoka',
        phone: '061234567',
        businessKind: 'restaurant',
        businessName: 'Chez Awa',
      }),
    ).toThrow(/téléphone international/)
    expect(() =>
      createOwnerSignupDetails({
        firstName: 'Awa',
        lastName: 'Yoka',
        phone: '+242061234567',
        businessKind: 'hospital',
        businessName: 'Chez Awa',
      }),
    ).toThrow(/activité proposée/)
  })

  it('preserves old accounts with legacy or absent metadata', () => {
    expect(ownerOnboardingHints(null).businessKind).toBe('retail')
    expect(ownerOnboardingHints({ business_kind: 'not-real' }).businessKind).toBe('retail')
  })
})
