// Who keeps the notebook: initials and name shown on the shop label and the menu button.

/** Words skipped when taking initials from a shop name (« Chez Mama Grâce » → « MG »). */
const smallWords = new Set([
  'chez',
  'boutique',
  'la',
  'le',
  'les',
  'de',
  'du',
  'des',
  'et',
  'au',
  'aux',
  'à',
  'l',
  'd',
])

/** Up to two upper-case initials of a person's or a shop's name (« ? » when there is none). */
export function initials(name: string | null | undefined): string {
  const words = (name ?? '')
    .split(/[\s'’-]+/)
    .map((w) => w.replace(/[^\p{L}\p{N}]/gu, ''))
    .filter(Boolean)
  const meaningful = words.filter((w) => !smallWords.has(w.toLowerCase()))
  const picked = (meaningful.length ? meaningful : words).slice(0, 2)
  const letters = picked.map((w) => w[0].toLocaleUpperCase('fr-FR')).join('')
  return letters || '?'
}

/** Name to show for the signed-in person: their full name if known (Google), else nothing. */
export function ownerName(metadata: Record<string, unknown> | null | undefined): string | null {
  const value = metadata?.full_name ?? metadata?.name
  return typeof value === 'string' && value.trim() ? value.trim() : null
}

/** « Grâce Mabiala » → « Grâce M. » (as written on the notebook label). */
export function shortName(name: string): string {
  const [first, ...rest] = name.split(/\s+/).filter(Boolean)
  const last = rest[rest.length - 1]
  return last ? `${first} ${last[0].toLocaleUpperCase('fr-FR')}.` : first
}
