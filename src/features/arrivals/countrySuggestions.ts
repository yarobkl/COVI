// Countries offered under « Pays d’origine » (and « Acheté où ? » for a bale).
import { countries } from '../../lib/countries'
import { normalize } from '../sale/saleMath'

/** Countries the shops buy from most, offered before anything is typed. */
const usual = {
  order: ['CN', 'IN', 'TR', 'AE', 'NG'],
  balloon: ['BE', 'FR', 'GB', 'CA', 'US'],
} as const
export type CountryKind = keyof typeof usual

const nameOf = (code: string) => countries.find((c) => c.code === code)?.name ?? code

/** Countries whose name starts with what was typed (then those containing it), five at most. */
export function countrySuggestions(typed: string, kind: CountryKind, max = 5) {
  const q = normalize(typed)
  if (!q) return usual[kind].map(nameOf)
  const names = countries.map((c) => c.name)
  if (names.some((n) => normalize(n) === q)) return []
  const known = new Set([...usual.order, ...usual.balloon].map(nameOf))
  const starts = names.filter((n) => normalize(n).startsWith(q))
  const inside = names.filter((n) => !normalize(n).startsWith(q) && normalize(n).includes(q))
  // The countries the shops buy from come first: « tur » offers Turquie before Turkménistan.
  const ranked = [...starts, ...inside].sort((a, b) => Number(known.has(b)) - Number(known.has(a)))
  return ranked.slice(0, max)
}
