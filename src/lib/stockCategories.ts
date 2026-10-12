/** Categories for COVI's future single stock per shop.
 * Pure helpers: no writes, no migration, no changes to the existing sales flow.
 * Keep historical product.category values untouched; normalization is for the new aggregated view.
 */
export const STOCK_CATEGORIES = [
  { key: 'chemises', label: 'Chemises' },
  { key: 'tshirts', label: 'T-shirts' },
  { key: 'polos', label: 'Polos' },
  { key: 'debardeurs', label: 'Débardeurs' },
  { key: 'pulls', label: 'Pulls' },
  { key: 'sweats', label: 'Sweats' },
  { key: 'gilets', label: 'Gilets' },
  { key: 'pantalons', label: 'Pantalons' },
  { key: 'jeans', label: 'Jeans' },
  { key: 'shorts', label: 'Shorts' },
  { key: 'bermudas', label: 'Bermudas' },
  { key: 'jupes', label: 'Jupes' },
  { key: 'robes', label: 'Robes' },
  { key: 'vestes', label: 'Vestes' },
  { key: 'manteaux', label: 'Manteaux' },
  { key: 'ensembles', label: 'Ensembles' },
  { key: 'costumes', label: 'Costumes' },
  { key: 'sport', label: 'Vêtements de sport' },
  { key: 'enfants', label: 'Vêtements enfants et bébés' },
  { key: 'sous-vetements', label: 'Sous-vêtements' },
  { key: 'boxers', label: 'Boxers' },
  { key: 'slips', label: 'Slips' },
  { key: 'culottes', label: 'Culottes' },
  { key: 'soutiens-gorge', label: 'Soutiens-gorge' },
  { key: 'chaussettes', label: 'Chaussettes' },
  { key: 'chaussures', label: 'Chaussures' },
  { key: 'sacs', label: 'Sacs' },
  { key: 'accessoires', label: 'Accessoires' },
  { key: 'linge-maison', label: 'Linge de maison' },
  { key: 'autres', label: 'Autres' },
] as const

export type StockCategoryKey = (typeof STOCK_CATEGORIES)[number]['key']

export function categoryKey(value: string): string {
  return value.trim().normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('fr')
    .replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'autres'
}

export type StockCategoryQuantity = { category: string; quantity: number }

/** Aggregate non-negative whole quantities; reject malformed rows rather than silently corrupting stock. */
export function aggregateCategoryStock(rows: readonly StockCategoryQuantity[]) {
  const totals = new Map<string, number>()
  for (const row of rows) {
    if (!Number.isSafeInteger(row.quantity) || row.quantity < 0)
      throw new Error('Quantité de stock invalide.')
    const key = categoryKey(row.category)
    const total = (totals.get(key) ?? 0) + row.quantity
    if (!Number.isSafeInteger(total)) throw new Error('Quantité de stock trop élevée.')
    totals.set(key, total)
  }
  return [...totals].map(([category, quantity]) => ({ category, quantity }))
}
