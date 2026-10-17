/** Business vocabulary, shared by signup and sector-specific views. */
export const BUSINESS_KINDS = [
  {
    value: 'retail',
    label: 'Boutique',
    nameLabel: 'Nom de la boutique',
    example: 'Ex. Chez Mama Grâce',
    preview: 'Votre boutique',
  },
  {
    value: 'restaurant',
    label: 'Restaurant',
    nameLabel: 'Nom du restaurant',
    example: 'Ex. Chez Maman',
    preview: 'Votre restaurant',
  },
  {
    value: 'salon',
    label: 'Salon de coiffure',
    nameLabel: 'Nom du salon',
    example: 'Ex. Salon Élégance',
    preview: 'Votre salon',
  },
] as const

export type BusinessKind = (typeof BUSINESS_KINDS)[number]['value']

export function businessKindInfo(kind: string | null | undefined) {
  return BUSINESS_KINDS.find((item) => item.value === kind) ?? BUSINESS_KINDS[0]
}

export function isBusinessKind(value: string): value is BusinessKind {
  return BUSINESS_KINDS.some((item) => item.value === value)
}
