import { describe, expect, it } from 'vitest'
import {
  CEMAC_COUNTRIES,
  administrativeAreas,
  neighborhoodsForArea,
  isValidBusinessAddress,
} from './cemacAreas'

describe('CEMAC establishment addresses', () => {
  it('lists the six member states with Congo first', () => {
    expect(CEMAC_COUNTRIES).toEqual([
      'République du Congo',
      'Cameroun',
      'Gabon',
      'République centrafricaine',
      'Guinée équatoriale',
      'Tchad',
    ])
  })

  it('keeps verified arrondissement lists separate from quartiers', () => {
    expect(administrativeAreas('République du Congo', 'Brazzaville')).toHaveLength(9)
    expect(administrativeAreas('République du Congo', 'Pointe-Noire')).toHaveLength(6)
    expect(administrativeAreas('Cameroun', 'Yaoundé')).toHaveLength(7)
    expect(administrativeAreas('Cameroun', 'Douala')).toHaveLength(6)
    expect(neighborhoodsForArea('République du Congo', 'Brazzaville', 'Moungali')).toContain(
      'Moukondo',
    )
    expect(neighborhoodsForArea('République du Congo', 'Brazzaville', 'Bacongo')).not.toContain(
      'Moukondo',
    )
    expect(administrativeAreas('Gabon', 'Libreville')).toEqual([])
  })

  it('requires a plausible descriptive physical address even without a street number', () => {
    expect(isValidBusinessAddress('')).toBe(false)
    expect(isValidBusinessAddress('Brazzaville')).toBe(false)
    expect(isValidBusinessAddress('Avenue de la Paix, près du marché')).toBe(true)
    expect(isValidBusinessAddress('00000000000000')).toBe(false)
  })
})
