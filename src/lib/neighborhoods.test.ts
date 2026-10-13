import { describe, expect, it } from 'vitest'
import { OTHER_NEIGHBORHOOD, neighborhoodSuggestions, resolveNeighborhood } from './neighborhoods'

describe('quartier / secteur selected by city', () => {
  it('shows the districts and sectors of Brazzaville and Pointe-Noire separately', () => {
    const brazza = neighborhoodSuggestions('Congo', 'Brazzaville')
    const pointe = neighborhoodSuggestions('République du Congo', 'Pointe-Noire')
    expect(brazza).toContain('Poto-Poto')
    expect(brazza).toContain('Moungali')
    expect(pointe).toContain('Ngoyo')
    expect(brazza).not.toContain('Ngoyo')
    expect(pointe).not.toContain('Moungali')
  })

  it('does not mix cities or countries, always supporting manual entry elsewhere', () => {
    expect(neighborhoodSuggestions('Gabon', 'Libreville')).toContain('Glass')
    expect(neighborhoodSuggestions('Cameroun', 'Douala')).toContain('Akwa')
    expect(neighborhoodSuggestions('République du Congo', 'Libreville')).toEqual([])
    expect(neighborhoodSuggestions('République du Congo', 'Dolisie')).toEqual([])
  })

  it('preserves previously entered quarters, including unknown neighborhoods', () => {
    expect(resolveNeighborhood('Poto Poto', 'Congo', 'Brazzaville')).toBe('Poto-Poto')
    expect(resolveNeighborhood('Quartier personnel', 'Congo', 'Brazzaville')).toBe(
      OTHER_NEIGHBORHOOD,
    )
    expect(resolveNeighborhood(null, 'Congo', 'Brazzaville')).toBe('')
  })
})
