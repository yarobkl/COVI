/**
 * CEMAC countries, focused geographic catalog for new PME registrations.
 * Source: https://cemac.int/about/
 *
 * Only VERIFIED municipality divisions are enumerated. Other towns/cities can
 * enter their administrative division manually instead of being forced to pick
 * an unrelated arrondissement. The directory is deliberately not exhaustive.
 */
export const CEMAC_COUNTRIES = [
  'République du Congo',
  'Cameroun',
  'Gabon',
  'République centrafricaine',
  'Guinée équatoriale',
  'Tchad',
] as const

export const OTHER_ADMIN_AREA = '__other_admin_area__'

const ADMINISTRATIVE_AREAS: Readonly<Record<string, readonly string[]>> = {
  // Congo ministry: https://www.developpement-durable.gouv.cg/2017/06/05/brazzaville-brazza-la-verte/
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
  ],
  // https://www.adiac-congo.com/node/137583
  'République du Congo|Pointe-Noire': [
    'Lumumba',
    'Mvoumvou',
    'Tié-Tié',
    'Loandjili',
    'Mongo-Mpoukou',
    'Ngoyo',
  ],
  // Urban Council: https://yaounde.cm/communes-darrondissement/
  'Cameroun|Yaoundé': [
    'Yaoundé I',
    'Yaoundé II',
    'Yaoundé III',
    'Yaoundé IV',
    'Yaoundé V',
    'Yaoundé VI',
    'Yaoundé VII',
  ],
  // Cameroun INS: https://stat.cm/nada/index.php/catalog/114/download/973
  'Cameroun|Douala': [
    'Douala I',
    'Douala II',
    'Douala III',
    'Douala IV',
    'Douala V',
    'Douala VI',
  ],
}

/** Certified suggestions for a few known arrondissements, not exhaustive. */
const NEIGHBORHOODS: Readonly<Record<string, readonly string[]>> = {
  // City neighborhood descriptions; manual entry remains available.
  'République du Congo|Brazzaville|Moungali': [
    'Plateau des 15 ans',
    'Marché Moungali',
    'Batignolles',
    'Moukondo',
  ],
  'République du Congo|Brazzaville|Talangaï': [
    'Mpila',
    'Intendance',
    'Texaco Tsiémé',
    'Champ de Tir',
    'Joseph Ngobali',
    'Liberté',
    'Simba Pelle',
    'Maman Mboualé',
    'Ngamakosso',
    'Manianga',
  ],
  'République du Congo|Brazzaville|Bacongo': [
    'Dahomey',
    'Mbama',
    'Mpissa',
    'Moukoundzi-Ngouaka',
  ],
}

/** Returns only the known divisions for the requested city (no cross-city mixing). */
export function administrativeAreas(country: string, city: string): readonly string[] {
  return ADMINISTRATIVE_AREAS[`${country.trim()}|${city.trim()}`] ?? []
}

export function neighborhoodsForArea(
  country: string,
  city: string,
  area: string,
): readonly string[] {
  return NEIGHBORHOODS[`${country.trim()}|${city.trim()}|${area.trim()}`] ?? []
}

/**
 * Textual address is required at establishment creation, even without a formal
 * street-numbering system. This validates completeness, not geocoding truth.
 */
export function isValidBusinessAddress(address: string): boolean {
  const value = address.trim().replace(/\s+/g, ' ')
  return value.length >= 10 && value.length <= 240 && /\p{L}/u.test(value) && value.includes(' ')
}

export function isCemacCountry(country: string): boolean {
  return (CEMAC_COUNTRIES as readonly string[]).includes(country)
}
