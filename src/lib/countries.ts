const names = new Intl.DisplayNames(['fr'], { type: 'region' })
const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
const codes = Array.from(
  { length: 26 * 26 },
  (_, i) => letters[Math.floor(i / 26)] + letters[i % 26],
)
const unknown = new Set(['région inconnue', 'unknown region'])
export const countries = codes
  .map((code) => ({ code, name: names.of(code) || code }))
  .filter(
    (country) =>
      country.name !== country.code && !unknown.has(country.name.toLocaleLowerCase('fr')),
  )
  .map((country) => ({
    ...country,
    flag:
      country.code === 'XK'
        ? '🇽🇰'
        : String.fromCodePoint(...[...country.code].map((c) => 127397 + c.charCodeAt(0))),
  }))
  .sort((a, b) => a.name.localeCompare(b.name, 'fr'))


/** Central Africa shown first on supplier receipts, with the REST of the world still selectable. */
import { CENTRAL_AFRICA } from './centralAfricaLocations'

const centralAfricaIsoCodes: Record<string, string> = {
  'République du Congo': 'CG',
  'République démocratique du Congo': 'CD',
  Cameroun: 'CM',
  Gabon: 'GA',
  'République centrafricaine': 'CF',
  Tchad: 'TD',
  'Guinée équatoriale': 'GQ',
  'São Tomé-et-Príncipe': 'ST',
  Angola: 'AO',
  Burundi: 'BI',
  Rwanda: 'RW',
}

const priorityCountries = CENTRAL_AFRICA.map(({ country }) => ({
  name: country,
  code: centralAfricaIsoCodes[country],
  flag: countries.find((c) => c.code === centralAfricaIsoCodes[country])?.flag ?? '',
}))

/** The supplier origin is worldwide; unlike a boutique address it has no dependent city. */
export const arrivalCountrySuggestions = [
  ...priorityCountries,
  ...countries.filter((item) => !priorityCountries.some((priority) => priority.name === item.name)),
]
