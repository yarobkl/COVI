// Display helpers shared by every page. Keep this module free of imports: tests/offline.mjs loads
// covi.ts (which imports it) from source.

/** No-break space (U+00A0). The app fonts lack the narrow one (U+202F) that fr-FR produces. */
export const NBSP = String.fromCharCode(0xa0)
/** True minus sign (U+2212), used for money going out (« − 90 000 »). */
export const MINUS = String.fromCharCode(0x2212)

const groupFormat = new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 0 })

/**
 * Whole CFA francs grouped by thousands with no-break spaces: `fcfa(126000)` → « 126 000 ».
 * Negative amounts start with the true minus sign: `fcfa(-90000)` → « − 90 000 ».
 */
export function fcfa(n: number) {
  const rounded = Math.round(Math.abs(n))
  const digits = groupFormat.format(rounded).replace(/\s/g, NBSP)
  return n < 0 && rounded !== 0 ? `${MINUS}${NBSP}${digits}` : digits
}

/** Amount followed by the currency: `money(15000)` → « 15 000 FCFA ». */
export const money = (n: number) => `${fcfa(n)}${NBSP}FCFA`

/** Percentage with the French no-break space: `percent(74)` → « 74 % ». */
export const percent = (n: number) => `${Math.round(n)}${NBSP}%`

/** Digits typed in an amount field, as a number (`null` when there are none): « 13 000 » → 13000. */
export function parseAmount(text: string): number | null {
  const digits = text.replace(/\D/g, '').slice(0, 12)
  return digits ? Number(digits) : null
}

/** Payment methods offered at checkout: label shown to the user and code stored in `sales`. */
export const paymentMethods = [
  { label: 'Espèces', code: 'cash' },
  { label: 'Mobile Money', code: 'mobile_money' },
  { label: 'Carte', code: 'card' },
  { label: 'Virement', code: 'bank_transfer' },
  { label: 'Autre', code: 'other' },
] as const

export const paymentLabels = paymentMethods.map((m) => m.label)

/** Code stored in the database for a checkout label (`other` when unknown). */
export const paymentCode = (label: string): string =>
  paymentMethods.find((m) => m.label === label)?.code ?? 'other'

/** Label shown for a stored payment code (the code itself when unknown). */
export const paymentLabel = (code: string): string =>
  paymentMethods.find((m) => m.code === code)?.label ?? code

/** How it was paid, as said at the counter: « en espèces », « par carte »… (label or code). */
export function paidWith(method: string): string {
  switch (paymentLabel(method) === method ? paymentCode(method) : method) {
    case 'cash':
      return 'en espèces'
    case 'mobile_money':
      return 'en Mobile Money'
    case 'card':
      return 'par carte'
    case 'bank_transfer':
      return 'par virement'
    default:
      return 'autrement'
  }
}

/**
 * Word agreeing with `count` under the French rule: singular below 2 (0 and 1), plural from 2.
 * `pluralForm` defaults to the singular followed by « s ».
 */
export const pluralize = (count: number, singular: string, pluralForm = singular + 's') =>
  Math.abs(count) < 2 ? singular : pluralForm

/** Count followed by the agreeing word: « 1 vente », « 2 ventes ». */
export const plural = (count: number, singular: string, pluralForm?: string) =>
  `${count} ${pluralize(count, singular, pluralForm)}`
