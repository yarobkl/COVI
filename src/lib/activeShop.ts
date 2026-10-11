// The shop a signed-in owner is working in, remembered per user on this device
// (`covi:active-shop:<userId>`). It is an interface preference, NEVER an authorization: the shop
// is only opened when its id is in the list the database returned for this account (RLS), or —
// when that list cannot be loaded (no network) — from this user's own copy on this device.
// Another account on the same phone has its own key and can never open this shop. Storage can be
// missing or blocked (private window): nothing breaks, the owner is simply asked again.

const key = (userId: string) => `covi:active-shop:${userId}`

type Remembered<T> = { id: string; shop?: T }

function read<T>(userId: string): Remembered<T> | null {
  try {
    const raw = localStorage.getItem(key(userId))
    if (!raw) return null
    // A copy of the shop (to reopen it without network), or just its id.
    if (raw.startsWith('{')) {
      const value = JSON.parse(raw) as { id?: unknown }
      return typeof value.id === 'string' ? { id: value.id, shop: value as T } : null
    }
    return { id: raw }
  } catch {
    return null
  }
}

/** Id of the shop last opened by this user on this device, if any. */
export function readActiveShop(userId: string): string | null {
  return read(userId)?.id ?? null
}

/** This user's copy of that shop, to reopen it when the shop list cannot be loaded. */
export function readActiveShopCopy<T extends { id: string }>(userId: string): T | null {
  return read<T>(userId)?.shop ?? null
}

export function rememberActiveShop<T extends { id: string }>(userId: string, shop: T) {
  try {
    localStorage.setItem(key(userId), JSON.stringify(shop))
  } catch {
    // Not remembered: the owner will choose again next time.
  }
}

export function forgetActiveShop(userId: string) {
  try {
    localStorage.removeItem(key(userId))
  } catch {
    // Nothing to forget.
  }
}

export type ShopChoice<T> = { kind: 'create' } | { kind: 'open'; shop: T } | { kind: 'choose' }

/**
 * What to show once the owner's shops are RECEIVED from the database (a failed load is not an
 * empty list: see AuthGate): no shop → create the first one; one shop → open it; several → the
 * remembered one if it is still in the list, otherwise ask.
 */
export function chooseShop<T extends { id: string }>(
  shops: readonly T[],
  rememberedId: string | null,
): ShopChoice<T> {
  if (shops.length === 0) return { kind: 'create' }
  if (shops.length === 1) return { kind: 'open', shop: shops[0] }
  const remembered = rememberedId ? shops.find((s) => s.id === rememberedId) : undefined
  return remembered ? { kind: 'open', shop: remembered } : { kind: 'choose' }
}
