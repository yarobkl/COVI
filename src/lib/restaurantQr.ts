import { supabaseUrl } from './supabase'

export type RestaurantQrMenuItem = {
  id: string
  name: string
  category: string
  kind: 'dish' | 'drink' | 'dessert'
  priceXaf: number
  available: boolean
}
export type RestaurantQrCatalog = {
  restaurantName: string
  tableName: string
  capacity: number
  tableState: 'free' | 'collecting' | 'occupied'
  orderingOpen: false
  menu: RestaurantQrMenuItem[]
}
export const restaurantQrUrl =
  import.meta.env.VITE_COVI_RESTAURANT_QR_URL || `${supabaseUrl}/functions/v1/restaurant-qr`

/** Permanent table QR. Never contains shop IDs, session IDs or personal data. */
export const restaurantQrLink = (origin: string, token: string) =>
  `${origin}/#/table/${token}`

export function parseRestaurantQrHash(hash: string) {
  const match = /^#\/table\/([a-f0-9]{64})$/i.exec(hash)
  return match ? { kind: 'restaurantTable' as const, token: match[1].toLowerCase() } : null
}

export async function fetchRestaurantQr(token: string): Promise<RestaurantQrCatalog> {
  if (!/^[a-f0-9]{64}$/.test(token)) throw new Error('Ce QR code de table est invalide.')
  let response: Response
  try {
    response = await fetch(`${restaurantQrUrl}?table=${token}`, {
      method: 'GET',
      cache: 'no-store',
    })
  } catch {
    throw new Error('Connexion indisponible. Réessayez.')
  }
  if (!response.ok) {
    throw new Error(response.status === 503
      ? 'La carte du restaurant n’est pas encore disponible.'
      : 'Cette table est introuvable ou indisponible.')
  }
  const data: unknown = await response.json()
  if (!data || typeof data !== 'object' ||
    !('menu' in data) || !Array.isArray(data.menu) ||
    !('tableState' in data) || !['free','collecting','occupied'].includes(String(data.tableState)) ||
    !('orderingOpen' in data) || data.orderingOpen !== false) {
    throw new Error('La carte du restaurant est temporairement indisponible.')
  }
  return data as RestaurantQrCatalog
}
