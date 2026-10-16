// Mentions communes aux pages légales (confidentialité, conditions, aide) : un seul endroit à
// mettre à jour. Éditeur et contact choisis par le propriétaire de COVI.
export const legal = {
  editor: 'Elie Bakala',
  email: 'eliebakala@gmail.com',
  updatedOn: '16 octobre 2026',
} as const

export const legalMail = (subject?: string) =>
  `mailto:${legal.email}` + (subject ? `?subject=${encodeURIComponent(subject)}` : '')

/** Liens des trois pages publiques (#/confidentialite, #/conditions, #/aide). */
export const legalLinks = [
  { href: '#/conditions', label: 'Conditions d’utilisation' },
  { href: '#/confidentialite', label: 'Confidentialité' },
  { href: '#/aide', label: 'Aide et contact' },
] as const
