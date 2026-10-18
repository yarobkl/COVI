import { describe, expect, it } from 'vitest'
import { BUSINESS_KINDS, businessKindInfo, isBusinessKind } from './businessKinds'

describe('business kinds', () => {
  it('offers a store, restaurant and salon without changing the legacy default', () => {
    expect(BUSINESS_KINDS.map((kind) => kind.value)).toEqual(['retail', 'restaurant', 'salon'])
    expect(businessKindInfo(undefined).value).toBe('retail')
    expect(businessKindInfo('unrecognized').value).toBe('retail')
  })

  it('validates the supported sectors and their vocabulary', () => {
    expect(isBusinessKind('salon')).toBe(true)
    expect(isBusinessKind('restaurant')).toBe(true)
    expect(isBusinessKind('hotel')).toBe(false)
    expect(businessKindInfo('salon').nameLabel).toBe('Nom du salon')
  })
})
