// Price pad logic, kept apart from the component so that it can be tested on its own.

/** A key of the pad: a digit, « 000 » (CFA prices almost always end with it) or « effacer ». */
export type PadKey = '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' | '000' | 'back'

/** Longest price the pad accepts (999 999 999 FCFA). */
export const MAX_DIGITS = 9

/** Keys in display order, three per row. */
export const PAD_KEYS: readonly PadKey[] = [
  '1',
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '000',
  '0',
  'back',
]

/**
 * Value after pressing `key` on a pad showing `value` (`null` = nothing typed). Leading zeros are
 * dropped, « 000 » after nothing does nothing, and digits beyond MAX_DIGITS are ignored.
 */
export function pressKey(value: number | null, key: PadKey): number | null {
  const digits = value === null ? '' : String(value)
  if (key === 'back') {
    const rest = digits.slice(0, -1)
    return rest === '' ? null : Number(rest)
  }
  if (key === '000' && (digits === '' || digits === '0')) return value
  const next = (digits === '0' ? '' : digits) + key
  if (next.length > MAX_DIGITS) return value
  return Number(next)
}

/** Lowers a price by `step` without going under zero (−500 / −1 000 shortcuts). */
export const lowerBy = (value: number | null, step: number) => Math.max(0, (value ?? 0) - step)

/** What a physical key does on the pad (desktop): a pad key, `confirm` (Enter) or nothing. */
export function keyFromKeyboard(key: string): PadKey | 'confirm' | null {
  if (/^[0-9]$/.test(key)) return key as PadKey
  if (key === 'Backspace' || key === 'Delete') return 'back'
  if (key === 'Enter') return 'confirm'
  return null
}
