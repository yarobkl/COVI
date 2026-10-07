const names = new Intl.DisplayNames(['fr'], { type: 'region' })
const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
const codes = Array.from({ length: 26 * 26 }, (_, i) => letters[Math.floor(i / 26)] + letters[i % 26])
const unknown = new Set(['région inconnue', 'unknown region'])
export const countries = codes
  .map(code => ({ code, name: names.of(code) || code }))
  .filter(country => country.name !== country.code && !unknown.has(country.name.toLocaleLowerCase('fr')))
  .map(country => ({
    ...country,
    flag: country.code === 'XK' ? '🇽🇰' : String.fromCodePoint(...[...country.code].map(c => 127397 + c.charCodeAt(0))),
  }))
  .sort((a, b) => a.name.localeCompare(b.name, 'fr'))
