// The « Ajouter au stock » form, without its interface: what was typed becomes the product to
// save, or the messages to show under the fields.
import type { addProduct } from '../../lib/covi'
import { parseAmount } from '../../lib/format'
import type { Arrival } from '../../lib/types'

export type ProductValues = {
  name: string
  category: string
  brand: string
  size: string
  /** Displayed price as typed (« 18 000 »). */
  price: string
  unique: boolean
  quantity: number
  /** Arrival id, `''` for none. */
  arrivalId: string
  photo: File | null
}

export type ProductInput = Parameters<typeof addProduct>[1]
export type ProductErrors = Partial<Record<'name' | 'price' | 'quantity', string>>

export const emptyProduct = (arrival?: Pick<Arrival, 'id' | 'kind'> | null): ProductValues => ({
  name: '',
  category: '',
  brand: '',
  size: '',
  price: '',
  unique: arrival?.kind === 'balloon',
  quantity: 1,
  arrivalId: arrival?.id ?? '',
  photo: null,
})

/** Largest quantity typed for one model (a typo such as 1000 instead of 10 is stopped). */
export const MAX_QUANTITY = 999

/**
 * The product to save, or what to fix. A unique piece always counts 1; a piece of a bale is
 * always unique (the bale keeps one global cost, never a price per piece).
 */
export function productFromValues(
  values: ProductValues,
  arrivals: readonly Pick<Arrival, 'id' | 'kind' | 'is_test'>[],
): { input: ProductInput; errors: null } | { input: null; errors: ProductErrors } {
  const errors: ProductErrors = {}
  const name = values.name.trim()
  const price = parseAmount(values.price)
  const arrival = arrivals.find((a) => a.id === values.arrivalId) ?? null
  const unique = values.unique || arrival?.kind === 'balloon'
  const quantity = unique ? 1 : Math.floor(values.quantity)
  if (!name) errors.name = 'Indiquez le nom de l’article.'
  if (!price) errors.price = 'Indiquez le prix affiché, en FCFA.'
  if (!unique && !(quantity >= 1)) errors.quantity = 'Indiquez au moins 1 pièce.'
  else if (quantity > MAX_QUANTITY)
    errors.quantity = `${MAX_QUANTITY} pièces au plus pour un modèle. Vérifiez le nombre.`
  if (Object.keys(errors).length) return { input: null, errors }
  return {
    errors: null,
    input: {
      name,
      category: values.category.trim(),
      brand: values.brand.trim(),
      size: values.size.trim(),
      initial_sale_price: price ?? 0,
      quantity_on_hand: quantity,
      is_unique_piece: unique,
      arrival_id: arrival?.id ?? null,
      is_test: arrival?.is_test ?? false,
      image: values.photo,
    },
  }
}

const messageOf = (error: unknown) =>
  String((error as { message?: unknown } | null | undefined)?.message ?? error ?? '')

const offlineText =
  'Pas de réseau : rien n’est enregistré. Réessayez quand le réseau revient.'

/** What to tell when saving a product fails: what happened and what to do, never English. */
export function productSaveError(error: unknown): string {
  const m = messageOf(error).toLowerCase()
  if (m.includes('choisissez une image'))
    return 'Cette photo ne passe pas. Prenez une photo JPG ou PNG de moins de 5 Mo.'
  if (m.includes('photo n’a pas pu') || m.includes("photo n'a pas pu"))
    return 'La photo n’est pas partie, le réseau est trop faible. Réessayez, ou enregistrez l’article sans photo.'
  if (typeof navigator !== 'undefined' && !navigator.onLine) return offlineText
  if (m.includes('failed to fetch') || m.includes('network') || m.includes('load failed'))
    return offlineText
  if (m.includes('jwt') || m.includes('authentication') || m.includes('not authorized'))
    return 'Votre session a pris fin. Reconnectez-vous, puis réessayez.'
  return 'Ça n’a pas marché. Vérifiez le réseau puis réessayez.'
}
