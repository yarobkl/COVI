import { supabaseUrl } from './supabase'

export const restaurantGuestEnabled =
  import.meta.env.VITE_COVI_RESTAURANT_GUEST_ENABLED === 'true'

export const restaurantGuestUrl =
  import.meta.env.VITE_COVI_RESTAURANT_GUEST_URL ||
  `${supabaseUrl}/functions/v1/restaurant-guest`

export type GuestLine = {
  itemId: string
  name: string
  quantity: number
  unitPriceXaf: number
  mine: boolean
}
export type GuestBasketStatus = {
  expired?: boolean
  groupStatus?: 'collecting' | 'submitted'
  orderReference?: string | null
  isLeader?: boolean
  ready?: boolean
  participants?: number
  readyParticipants?: number
  lines?: GuestLine[]
}
export type GuestMembership = { participantToken: string; participantId: string }

export async function guestAction<T>(
  action: 'join' | 'choice' | 'ready' | 'status' | 'submit',
  table: string,
  options: Record<string, unknown>,
): Promise<T> {
  if (!restaurantGuestEnabled) throw new Error('Les commandes par QR ne sont pas encore activées.')
  if (!/^[a-f0-9]{64}$/.test(table)) throw new Error('QR de table invalide.')
  let response: Response
  try {
    response = await fetch(restaurantGuestUrl, {
      method: 'POST',
      cache: 'no-store',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ action, table, ...options }),
    })
  } catch {
    throw new Error('Connexion interrompue. Vérifiez votre réseau avant de réessayer.')
  }
  const data = await response.json().catch(() => null)
  if (!response.ok)
    throw new Error(
      data?.error && typeof data.error === 'string'
        ? data.error
        : 'La commande est momentanément indisponible.',
    )
  return data as T
}

const key = (table: string) => `covi-restaurant-guest:${table}`

export function readGuestToken(table: string): string {
  try {
    const token = window.sessionStorage.getItem(key(table)) ?? ''
    return /^[a-f0-9]{64}$/.test(token) ? token : ''
  } catch {
    return ''
  }
}
export function saveGuestToken(table: string, token: string) {
  if (!/^[a-f0-9]{64}$/.test(token)) throw new Error('Session client incorrecte.')
  window.sessionStorage.setItem(key(table), token)
}
export function clearGuestToken(table: string) {
  try { window.sessionStorage.removeItem(key(table)) } catch { /* private window */ }
}
