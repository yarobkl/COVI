/** Validate and combine quantities before a balloon or supplier reception is committed.
 * This module is intentionally independent from Supabase and the existing sale flow.
 */
import { categoryKey } from './stockCategories'

export type ReceptionLine = {
  category: string
  quantity: number
}

export type PreparedReceptionLine = {
  categoryKey: string
  quantity: number
}

export function prepareReceptionLines(lines: readonly ReceptionLine[]): PreparedReceptionLine[] {
  if (lines.length === 0) throw new Error('Ajoutez au moins une catégorie au ballon.')
  if (lines.length > 100) throw new Error('Trop de lignes pour une seule réception.')

  const totals = new Map<string, number>()
  for (const line of lines) {
    if (typeof line.category !== 'string' || !line.category.trim())
      throw new Error('La catégorie est obligatoire.')
    if (line.category.trim().length > 80) throw new Error('Le nom de catégorie est trop long.')
    if (!Number.isSafeInteger(line.quantity) || line.quantity <= 0)
      throw new Error('La quantité reçue doit être un entier positif.')
    const key = categoryKey(line.category)
    const total = (totals.get(key) ?? 0) + line.quantity
    if (!Number.isSafeInteger(total) || total > 2147483647)
      throw new Error('La quantité dépasse la limite autorisée.')
    totals.set(key, total)
  }

  return [...totals].map(([key, quantity]) => ({ categoryKey: key, quantity }))
}

/** No unit purchase price is inferred from the global cost of a balloon. */
export function validateReceptionCost(cost: number): number {
  if (!Number.isFinite(cost) || cost < 0 || !Number.isSafeInteger(cost))
    throw new Error('Le coût global doit être un montant entier positif ou nul.')
  return cost
}
