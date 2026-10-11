// Ma boutique: what can be changed (name, city, country) and what this device keeps.
import { longDay, clock, localDay } from '../../lib/dates'
import { supabase } from '../../lib/supabase'
import type { Shop } from '../../lib/types'

export type ShopDraft = { name: string; city: string; country: string }

/** The trimmed fields to save, or what to say when the name is missing. */
export function readShopDraft(draft: ShopDraft): { values: ShopDraft } | { error: string } {
  const values = {
    name: draft.name.trim(),
    city: draft.city.trim(),
    country: draft.country.trim(),
  }
  if (!values.name) return { error: 'Indiquez le nom de la boutique.' }
  return { values }
}

/** Saves the name, city and country of the shop; throws when the network does not answer. */
export async function saveShop(shop: Shop, values: ShopDraft): Promise<Shop> {
  const { error } = await supabase.from('shops').update(values).eq('id', shop.id)
  if (error) throw error
  return { ...shop, ...values }
}

/** « aujourd’hui à 14 h 32 », « hier à 9 h 05 », « jeudi 8 octobre à 14 h 32 ». */
export function copyDate(iso: string | null, now: Date = new Date()): string | null {
  if (!iso) return null
  const d = new Date(iso)
  if (Number.isNaN(d.getTime())) return null
  const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1)
  const day =
    localDay(d) === localDay(now)
      ? 'aujourd’hui'
      : localDay(d) === localDay(yesterday)
        ? 'hier'
        : longDay(d).toLowerCase()
  return `${day} à ${clock(d)}`
}
