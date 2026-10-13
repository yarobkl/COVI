import { resolveAfricanCountry } from './centralAfricaLocations'

/**
 * Conservative starter directory of documented urban sectors (including arrondissements
 * and communes, which are NOT always quartiers). City-level entries deliberately do
 * not pretend to cover every small quartier. Every city always offers manual entry.
 * Add more validated neighbourhoods incrementally with a verifiable source.
 */
export const OTHER_NEIGHBORHOOD = '__other_neighborhood__'

const sectorsByCity: Readonly<Record<string, readonly string[]>> = {
  'République du Congo|Brazzaville': [
    'Makélékélé',
    'Bacongo',
    'Poto-Poto',
    'Moungali',
    'Ouenzé',
    'Talangaï',
    'Mfilou',
    'Madibou',
    'Djiri',
    'Plateau des 15 ans',
    'Moukondo',
    'Dix Maisons',
  ],
  'République du Congo|Pointe-Noire': [
    'Lumumba',
    'Mvoumvou',
    'Tié-Tié',
    'Loandjili',
    'Mongo-Mpoukou',
    'Ngoyo',
    'Côte Matève',
    'Mpaka',
    'Tchimbambouka',
    'Djeno',
  ],
  'République démocratique du Congo|Kinshasa': [
    'Gombe',
    'Bandalungwa',
    'Barumbu',
    'Bumbu',
    'Kalamu',
    'Kasa-Vubu',
    'Kintambo',
    'Lemba',
    'Limete',
    'Lingwala',
    'Makala',
    'Masina',
    'Matete',
    'Ngaba',
    'Ngaliema',
    'Ngiri-Ngiri',
    'Selembao',
  ],
  'Cameroun|Douala': ['Akwa', 'Bali', 'Bonapriso', 'Bonamoussadi', 'Deido', 'Bépanda', 'New Bell'],
  'Cameroun|Yaoundé': ['Bastos', 'Biyem-Assi', 'Etoudi', 'Melen', 'Mendong', 'Mokolo', 'Nlongkak'],
  'Gabon|Libreville': ['Akébé', 'Glass', 'Lalala', 'Louis', 'Mont-Bouët', 'Nzeng-Ayong'],
}

/** Return curated suggestions for this exact pair; never mix neighbouring cities. */
export function neighborhoodSuggestions(country: string, city: string): readonly string[] {
  return sectorsByCity[`${resolveAfricanCountry(country)}|${city.trim()}`] ?? []
}

function folded(value: string): string {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLocaleLowerCase('fr')
    .replace(/[^a-z0-9]+/g, '')
}

/** Preserve any historical/free-text quartier not yet in the curated directory. */
export function resolveNeighborhood(
  saved: string | null | undefined,
  country: string,
  city: string,
): string {
  const trimmed = saved?.trim() ?? ''
  if (!trimmed) return ''
  return (
    neighborhoodSuggestions(country, city).find((entry) => folded(entry) === folded(trimmed)) ??
    OTHER_NEIGHBORHOOD
  )
}
