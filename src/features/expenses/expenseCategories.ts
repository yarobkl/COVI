/** Expense categories offered in the form, most frequent first (TON-ET-VOCABULAIRE.md § 3.12). */
export const expenseCategories = [
  'Loyer',
  'Électricité',
  'Eau',
  'Internet / forfait',
  'Crédit téléphone',
  'Salaires',
  'Prime',
  'Transport',
  'Livraison',
  'Carburant (groupe, moto)',
  'Porteurs / manutention',
  'Sacs et emballages',
  'Cintres',
  'Nettoyage',
  'Réparations',
  'Fournitures',
  'Publicité (Facebook, TikTok…)',
  'Influenceurs',
  'Frais bancaires',
  'Frais Mobile Money',
  'Patente, taxes, mairie',
  'Ticket de marché / droit de place',
  'Gardiennage',
  'Autre',
] as const

/** Names used before the rewrite, as they may still be stored, and the name shown today. */
const renamed: Record<string, string> = {
  Internet: 'Internet / forfait',
  Téléphone: 'Crédit téléphone',
  Salaire: 'Salaires',
  Carburant: 'Carburant (groupe, moto)',
  Manutention: 'Porteurs / manutention',
  Emballage: 'Sacs et emballages',
  Sacs: 'Sacs et emballages',
  'Publicité Facebook / Instagram / TikTok': 'Publicité (Facebook, TikTok…)',
  'Taxes / frais administratifs': 'Patente, taxes, mairie',
}

/** Category as shown today: old stored names are read with their new wording. */
export const categoryLabel = (category: string) => renamed[category] ?? category
