/** Single country/city catalog used in both onboarding and existing-shop settings. */
export const CENTRAL_AFRICA = [
  {
    country: 'République du Congo',
    cities: [
      'Brazzaville',
      'Pointe-Noire',
      'Dolisie',
      'Nkayi',
      'Ouesso',
      'Owando',
      'Oyo',
      'Impfondo',
      'Sibiti',
      'Madingou',
      'Kinkala',
      'Djambala',
      'Ewo',
      'Mossendjo',
      'Makoua',
      'Gamboma',
      'Mindouli',
      'Loango',
    ],
  },
  {
    country: 'République démocratique du Congo',
    cities: [
      'Kinshasa',
      'Lubumbashi',
      'Mbuji-Mayi',
      'Kananga',
      'Kisangani',
      'Goma',
      'Bukavu',
      'Kolwezi',
      'Likasi',
      'Matadi',
      'Kikwit',
      'Bunia',
      'Beni',
    ],
  },
  {
    country: 'Cameroun',
    cities: [
      'Yaoundé',
      'Douala',
      'Bafoussam',
      'Garoua',
      'Bamenda',
      'Maroua',
      'Ngaoundéré',
      'Bertoua',
      'Ebolowa',
      'Kribi',
      'Limbé',
      'Buéa',
    ],
  },
  {
    country: 'Gabon',
    cities: [
      'Libreville',
      'Port-Gentil',
      'Franceville',
      'Oyem',
      'Moanda',
      'Lambaréné',
      'Mouila',
      'Tchibanga',
      'Makokou',
    ],
  },
  {
    country: 'République centrafricaine',
    cities: ['Bangui', 'Bimbo', 'Berbérati', 'Bambari', 'Bouar', 'Bossangoa', 'Bria', 'Carnot'],
  },
  {
    country: 'Tchad',
    cities: ["N'Djamena", 'Moundou', 'Sarh', 'Abéché', 'Kélo', 'Doba', 'Koumra', 'Mongo', 'Pala'],
  },
  {
    country: 'Guinée équatoriale',
    cities: ['Malabo', 'Bata', 'Ebebiyín', 'Mongomo', 'Luba', 'Evinayong'],
  },
  {
    country: 'São Tomé-et-Príncipe',
    cities: ['São Tomé', 'Santo António', 'Trindade', 'Neves', 'Santana'],
  },
  {
    country: 'Angola',
    cities: [
      'Luanda',
      'Huambo',
      'Benguela',
      'Lobito',
      'Lubango',
      'Cabinda',
      'Malanje',
      'Namibe',
      'Soyo',
      'Uíge',
    ],
  },
  {
    country: 'Burundi',
    cities: ['Bujumbura', 'Gitega', 'Ngozi', 'Rumonge', 'Muyinga', 'Kayanza', 'Bururi'],
  },
  {
    country: 'Rwanda',
    cities: ['Kigali', 'Huye', 'Musanze', 'Rubavu', 'Muhanga', 'Rusizi', 'Nyagatare'],
  },
] as const

export const OTHER_CITY = '__other__'

/** Match historic country labels without silently discarding an existing value. */
function fold(value: string) {
  return value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '')
}

const legacyCountries: Record<string, string> = {
  congo: 'République du Congo',
  congobrazzaville: 'République du Congo',
  republicofcongo: 'République du Congo',
  drc: 'République démocratique du Congo',
  rdc: 'République démocratique du Congo',
  congokinshasa: 'République démocratique du Congo',
  democraticrepublicofcongo: 'République démocratique du Congo',
  centralafricanrepublic: 'République centrafricaine',
  rca: 'République centrafricaine',
  equatorialguinea: 'Guinée équatoriale',
  saotomeandprincipe: 'São Tomé-et-Príncipe',
  chad: 'Tchad',
  angola: 'Angola',
}

/** Canonicalize known historic spellings, but preserve unknown saved countries. */
export function resolveAfricanCountry(savedValue: string | null | undefined): string {
  const trimmed = savedValue?.trim() ?? ''
  if (!trimmed) return 'République du Congo'
  const key = fold(trimmed)
  const canonical = CENTRAL_AFRICA.find((item) => fold(item.country) === key)
  return canonical?.country ?? legacyCountries[key] ?? trimmed
}

export function listedAfricanCities(country: string): readonly string[] {
  return CENTRAL_AFRICA.find((item) => item.country === country)?.cities ?? []
}

/** Case/diacritic insensitive so legacy BRAZZAVILLE displays as Brazzaville. */
export function resolveAfricanCity(savedValue: string | null | undefined, country: string) {
  const trimmed = savedValue?.trim() ?? ''
  if (!trimmed) return ''
  const normalized = fold(trimmed)
  return listedAfricanCities(country).find((city) => fold(city) === normalized) ?? OTHER_CITY
}
