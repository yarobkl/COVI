import { describe, expect, it } from 'vitest'
import { CENTRAL_AFRICA } from './centralAfricaLocations'
import { arrivalCountrySuggestions, countries } from './countries'

describe('supplier origin country suggestions throughout COVI', () => {
  it('prioritizes all Central African countries without restricting worldwide suppliers', () => {
    expect(arrivalCountrySuggestions.slice(0, CENTRAL_AFRICA.length).map((c) => c.name)).toEqual(
      CENTRAL_AFRICA.map((c) => c.country),
    )
    for (const name of ['France', 'Chine', 'Inde', 'Émirats arabes unis']) {
      expect(arrivalCountrySuggestions.some((c) => c.name === name)).toBe(true)
    }
    expect(arrivalCountrySuggestions.length).toBeGreaterThanOrEqual(
      new Set(countries.map((c) => c.name)).size,
    )
  })

  it('does not repeat an identical country name in the suggestions', () => {
    const names = arrivalCountrySuggestions.map((c) => c.name)
    expect(new Set(names).size).toBe(names.length)
  })
})
