import { describe, expect, it } from 'vitest'
import {
  CENTRAL_AFRICA,
  listedAfricanCities,
  OTHER_CITY,
  resolveAfricanCity,
  resolveAfricanCountry,
} from './centralAfricaLocations'

describe('Central Africa location selectors', () => {
  it('reuses historical countries plus West African city suggestions', () => {
    expect(CENTRAL_AFRICA).toHaveLength(26)
    expect(CENTRAL_AFRICA.map((x) => x.country)).toContain('République du Congo')
    expect(CENTRAL_AFRICA.map((x) => x.country)).toContain('République démocratique du Congo')
    expect(CENTRAL_AFRICA.map((x) => x.country)).toContain('Gabon')
    expect(listedAfricanCities('République du Congo')).toContain('Brazzaville')
    expect(listedAfricanCities('Gabon')).toContain('Libreville')
    expect(listedAfricanCities('Cameroun')).toContain('Douala')
  })

  it('maps older Congo/Brazzaville records to the canonical selection', () => {
    expect(resolveAfricanCountry('Congo')).toBe('République du Congo')
    expect(resolveAfricanCountry('CONGO-BRAZZAVILLE')).toBe('République du Congo')
    expect(resolveAfricanCountry('RDC')).toBe('République démocratique du Congo')
    expect(resolveAfricanCountry('Gabon')).toBe('Gabon')
    expect(resolveAfricanCity('BRAZZAVILLE', 'République du Congo')).toBe('Brazzaville')
    expect(resolveAfricanCity('Pointe Noire', 'République du Congo')).toBe('Pointe-Noire')
  })

  it('retains a merchant’s custom country and city rather than losing them', () => {
    expect(resolveAfricanCountry('Pays personnalisé')).toBe('Pays personnalisé')
    expect(listedAfricanCities('Pays personnalisé')).toHaveLength(0)
    expect(resolveAfricanCity('Petit village', 'République du Congo')).toBe(OTHER_CITY)
    expect(resolveAfricanCity('Quartier 4', 'Pays personnalisé')).toBe(OTHER_CITY)
    expect(resolveAfricanCity('', 'République du Congo')).toBe('')
  })
})
