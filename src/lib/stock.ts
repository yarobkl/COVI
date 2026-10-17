// « Modifier le produit » : fiche (nom, prix…), corrections de stock avec motif, archivage.
// La quantité ne s'écrit jamais directement : seulement par une vente ou par adjust_product_stock,
// qui garde une trace (stock_movements). Les ventes ne sont jamais modifiées.
import { supabase } from './supabase'

export type StockReason = 'restock' | 'loss' | 'theft' | 'count_error'

export const stockReasons: readonly { value: StockReason; label: string; hint: string }[] = [
  { value: 'restock', label: 'Réassort', hint: 'Des exemplaires sont arrivés.' },
  { value: 'loss', label: 'Perte ou casse', hint: 'Abîmé, taché, perdu.' },
  { value: 'theft', label: 'Vol', hint: 'Disparu du rayon.' },
  { value: 'count_error', label: 'Erreur de comptage', hint: 'Le stock compté est différent.' },
]

export const stockReasonLabel = (reason: string) =>
  stockReasons.find((r) => r.value === reason)?.label ?? reason

export type StockMovement = {
  id: string
  product_id: string
  reason: StockReason
  quantity_before: number
  quantity_after: number
  note: string | null
  created_at: string
}

export type ProductDetails = {
  name: string
  category: string | null
  brand: string | null
  size: string | null
  initial_sale_price: number
}

// Les fonctions et la table récentes ne figurent pas encore dans les types générés de la base.
const db = supabase as unknown as {
  rpc: (
    name: string,
    args?: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: unknown }>
  from: (table: string) => {
    select: (columns: string) => {
      eq: (
        column: string,
        value: string,
      ) => {
        order: (
          column: string,
          options: { ascending: boolean },
        ) => { limit: (n: number) => PromiseLike<{ data: unknown; error: unknown }> }
      }
    }
    update: (values: Record<string, unknown>) => {
      eq: (column: string, value: string) => PromiseLike<{ data: unknown; error: unknown }>
    }
  }
}

async function run<T>(request: PromiseLike<{ data: unknown; error: unknown }>): Promise<T> {
  const { data, error } = await request
  if (error) throw error
  return data as T
}

/** Nouvelle quantité, avec un motif (et une note facultative). */
export const adjustProductStock = (
  productId: string,
  quantity: number,
  reason: StockReason,
  note: string,
) =>
  run<{ id: string; quantity_on_hand: number; status: string }>(
    db.rpc('adjust_product_stock', {
      p_product_id: productId,
      p_quantity: quantity,
      p_reason: reason,
      p_note: note.trim() || null,
    }),
  )

export const setProductArchived = (productId: string, archived: boolean) =>
  run<{ id: string; status: string }>(
    db.rpc('set_product_archived', { p_product_id: productId, p_archived: archived }),
  )

/** Nom, catégorie, marque, taille et prix de vente (colonnes modifiables par le propriétaire). */
export const updateProductDetails = (productId: string, details: ProductDetails) =>
  run<null>(db.from('products').update(details).eq('id', productId))

export const listStockMovements = (productId: string) =>
  run<StockMovement[]>(
    db
      .from('stock_movements')
      .select('id, product_id, reason, quantity_before, quantity_after, note, created_at')
      .eq('product_id', productId)
      .order('created_at', { ascending: false })
      .limit(20),
  )

/** Message de la base dans les mots de la boutique. */
export function stockErrorMessage(error: unknown): string {
  const message =
    error && typeof error === 'object' && 'message' in error
      ? String((error as { message: unknown }).message)
      : ''
  if (message.includes('Restock must increase'))
    return 'Un réassort ajoute des exemplaires : la nouvelle quantité doit être plus grande.'
  if (message.includes('Loss must decrease'))
    return 'Une perte ou un vol retire des exemplaires : la nouvelle quantité doit être plus petite.'
  if (message.includes('Stock unchanged')) return 'C’est déjà la quantité en stock.'
  if (message.includes('Unique piece')) return 'Une pièce unique ne peut être qu’à 0 ou 1.'
  if (message.includes('Invalid stock quantity')) return 'Indiquez une quantité entre 0 et 100 000.'
  if (message.includes('Invalid stock note')) return 'La note est trop longue (200 caractères).'
  if (message.includes('initial_sale_price')) return 'Le prix ne peut pas être négatif.'
  return 'L’enregistrement n’a pas abouti. Vérifiez la connexion et réessayez.'
}
