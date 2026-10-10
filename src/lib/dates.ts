// Calendar keys in the device's local time zone (toISOString() would shift them to UTC).
const pad = (n: number) => String(n).padStart(2, '0')
export const localMonth = (d: Date = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}`
export const localDay = (d: Date = new Date()) => `${localMonth(d)}-${pad(d.getDate())}`

// Dates as people say them (« jeudi 8 octobre », « 14 h 32 »), never 2026-10-02.
const months = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
]
const shortMonths = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
]
const weekdays = ['dimanche', 'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi']

/** « Jeudi 8 octobre ». */
export const longDay = (d: Date) => {
  const s = `${weekdays[d.getDay()]} ${d.getDate()} ${months[d.getMonth()]}`
  return s.charAt(0).toUpperCase() + s.slice(1)
}
/** Month name, lower case: « octobre ». */
export const monthName = (d: Date) => months[d.getMonth()]
/** « 2 oct. ». */
export const shortDay = (d: Date) => `${d.getDate()} ${shortMonths[d.getMonth()]}`
/** « 14 h 32 » (spoken French time). */
export const clock = (d: Date) => `${d.getHours()} h ${pad(d.getMinutes())}`
/** « 14:32 » (as printed on a till receipt). */
export const ticketClock = (d: Date) => `${pad(d.getHours())}:${pad(d.getMinutes())}`
/** « 08/10 » (receipt). */
export const ticketDay = (d: Date) => `${pad(d.getDate())}/${pad(d.getMonth() + 1)}`

/** « aujourd’hui 14 h 32 », « hier 18 h 05 », « 2 oct. 11 h 48 ». */
export function whenLabel(d: Date, now: Date = new Date()) {
  if (localDay(d) === localDay(now)) return `aujourd’hui ${clock(d)}`
  const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
  if (localDay(d) === localDay(yesterday)) return `hier ${clock(d)}`
  return `${shortDay(d)} ${clock(d)}`
}
