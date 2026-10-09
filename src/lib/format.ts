// Display helpers shared by every page. Keep this module free of imports: tests/offline.mjs loads
// covi.ts (which imports it) from source.

const amountFormat = new Intl.NumberFormat('fr-FR')

/** Amount in CFA francs, e.g. `money(15000)` → `15 000 FCFA` (French digit grouping). */
export const money = (n: number) => amountFormat.format(n) + ' FCFA'

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

/**
 * Word agreeing with `count` under the French rule: singular below 2 (0 and 1), plural from 2.
 * `pluralForm` defaults to the singular followed by « s ».
 */
export const pluralize = (count: number, singular: string, pluralForm = singular + 's') =>
  Math.abs(count) < 2 ? singular : pluralForm

/** Count followed by the agreeing word: « 1 vente », « 2 ventes ». */
export const plural = (count: number, singular: string, pluralForm?: string) =>
  `${count} ${pluralize(count, singular, pluralForm)}`
