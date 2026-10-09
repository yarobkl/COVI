export type PendingSale = {
  id: string
  shopId: string
  productId: string
  quantity: number
  soldUnitPrice: number
  paymentLabel: string
  createdAt: string
  attempts: number
  lastError?: string
  userId?: string
}
export type RejectedSale = PendingSale & { reason: string; rejectedAt: string; dismissed?: boolean }
/** `message` of a thrown value (errors from Supabase are plain objects, not Error instances). */
const errorMessage = (e: unknown) => (e as { message?: unknown } | null | undefined)?.message
const KEY = 'covi:pending-sales:v1'
const LEGACY_REJECTED_KEY = 'covi:rejected-sales:v1'
const REJECTED_KEY = 'covi:rejected-sales:v2'
// Each queued sale belongs to the account that recorded it and is only synced while that account is signed in. Entries queued before userId existed are synced by whoever is signed in.
let activeUser: string | null = null
const mine = (x: PendingSale) => !x.userId || x.userId === activeUser
export function setSyncUser(userId: string | null) {
  if (userId === activeUser) return
  activeUser = userId
  resetSyncBackoff()
  window.dispatchEvent(new Event('covi-sync'))
}
const readRejected = (): RejectedSale[] => {
  try {
    return JSON.parse(localStorage.getItem(REJECTED_KEY) || '[]')
  } catch {
    return []
  }
}
export const rejectedSales = () => readRejected().filter(mine)
export const rejectedSaleCount = () =>
  Number(localStorage.getItem(LEGACY_REJECTED_KEY) || 0) +
  rejectedSales().filter((x) => !x.dismissed).length
export function clearRejectedSaleCount() {
  localStorage.removeItem(LEGACY_REJECTED_KEY)
  localStorage.setItem(
    REJECTED_KEY,
    JSON.stringify(readRejected().map((x) => (mine(x) ? { ...x, dismissed: true } : x))),
  )
  window.dispatchEvent(new Event('covi-sync'))
}
const read = (): PendingSale[] => {
  try {
    return JSON.parse(localStorage.getItem(KEY) || '[]')
  } catch {
    return []
  }
}
const write = (x: PendingSale[]) => localStorage.setItem(KEY, JSON.stringify(x))
export const pendingSales = () => read().filter(mine)
export const pendingCount = () => pendingSales().length
export function queueSale(
  input: Omit<PendingSale, 'id' | 'createdAt' | 'attempts' | 'userId'> & { userId: string },
  operationId = crypto.randomUUID(),
) {
  const x: PendingSale = {
    ...input,
    id: operationId,
    createdAt: new Date().toISOString(),
    attempts: 0,
  }
  write([...read(), x])
  reserveOfflineStock(input.shopId, input.productId, input.quantity)
  window.dispatchEvent(new Event('covi-sync'))
  return x
}
let syncInProgress = false,
  retryDelay = 0,
  retryAt = 0,
  retryTimer: ReturnType<typeof setTimeout> | undefined
// Network-like failures (server down, expired JWT while navigator.onLine is true) back off exponentially: 5 s, 10 s, 20 s… capped at 5 min, with a single pending retry timer.
const RETRY_BASE_MS = 5000,
  RETRY_MAX_MS = 300000
export const nextSyncRetryAt = () => retryAt
function resetSyncBackoff() {
  retryDelay = 0
  retryAt = 0
  if (retryTimer !== undefined) {
    clearTimeout(retryTimer)
    retryTimer = undefined
  }
}
function scheduleSyncRetry() {
  retryDelay = retryDelay ? Math.min(retryDelay * 2, RETRY_MAX_MS) : RETRY_BASE_MS
  retryAt = Date.now() + retryDelay
  if (retryTimer !== undefined) clearTimeout(retryTimer)
  retryTimer = setTimeout(() => {
    retryTimer = undefined
    void syncPendingSales()
  }, retryDelay)
}
if (typeof window !== 'undefined') window.addEventListener('online', resetSyncBackoff)
export async function syncPendingSales() {
  const user = activeUser
  if (!navigator.onLine || syncInProgress || !user || Date.now() < retryAt)
    return { synced: 0, pending: pendingCount(), rejected: 0 }
  syncInProgress = true
  let synced = 0,
    rejected = 0,
    failed = false
  try {
    for (const item of read().filter(mine)) {
      if (activeUser !== user) break
      try {
        const { recordSale } = await import('./covi')
        await recordSale(
          item.shopId,
          item.productId,
          item.quantity,
          item.soldUnitPrice,
          item.paymentLabel,
          item.id,
        )
        write(read().filter((x) => x.id !== item.id))
        synced++
      } catch (e) {
        const message = String(errorMessage(e) || 'Erreur de synchronisation'),
          network =
            /fetch|network|offline|failed to fetch|timeout|jwt|token|unauthorized|401|not authenticated/i.test(
              message,
            )
        if (network) {
          write(
            read().map((x) =>
              x.id === item.id ? { ...x, attempts: x.attempts + 1, lastError: message } : x,
            ),
          )
          failed = true
          break
        }
        localStorage.setItem(
          REJECTED_KEY,
          JSON.stringify([
            ...readRejected(),
            {
              ...item,
              userId: item.userId ?? user,
              reason: message,
              rejectedAt: new Date().toISOString(),
            },
          ]),
        )
        write(read().filter((x) => x.id !== item.id))
        restoreOfflineStock(item.shopId, item.productId, item.quantity)
        rejected++
      }
    }
  } finally {
    syncInProgress = false
    if (failed) scheduleSyncRetry()
    else resetSyncBackoff()
    if (synced || rejected || activeUser !== user) window.dispatchEvent(new Event('covi-sync'))
  }
  return { synced, pending: pendingCount(), rejected }
}
export async function resilientSale(input: {
  shopId: string
  productId: string
  quantity: number
  soldUnitPrice: number
  paymentLabel: string
}) {
  const operationId = crypto.randomUUID(),
    userId = activeUser,
    queue = () => {
      if (!userId)
        throw new Error('Session introuvable. Reconnectez-vous pour enregistrer cette vente.')
      assertOfflineStock(input.shopId, input.productId, input.quantity)
      queueSale({ ...input, userId }, operationId)
      return { offline: true }
    }
  if (!navigator.onLine) return queue()
  try {
    const { recordSale } = await import('./covi')
    await recordSale(
      input.shopId,
      input.productId,
      input.quantity,
      input.soldUnitPrice,
      input.paymentLabel,
      operationId,
    )
    return { offline: false }
  } catch (e) {
    const network = /fetch|network|offline|failed to fetch/i.test(String(errorMessage(e) || e))
    if (!network) throw e
    return queue()
  }
}

const stockKey = (shopId: string) => 'covi:stock:' + shopId
/** Fields of a cached product that the offline queue reads; other fields are kept as they are. */
type StockEntry = { id: string; quantity_on_hand: number; status: string }
export function cachedStock<T>(shopId: string): T[] {
  try {
    return JSON.parse(localStorage.getItem(stockKey(shopId)) || '[]')
  } catch {
    return []
  }
}
export function cacheStock<T>(shopId: string, products: T[]) {
  localStorage.setItem(stockKey(shopId), JSON.stringify(products))
  localStorage.setItem(stockKey(shopId) + ':at', new Date().toISOString())
}
// Server stock does not yet include queued offline sales: keep them reserved so a refresh cannot re-open sold pieces offline.
export function cacheServerStock<
  T extends { id: string; quantity_on_hand: number; status: string },
>(shopId: string, products: T[]) {
  const held = new Map<string, number>()
  for (const s of read())
    if (s.shopId === shopId)
      held.set(s.productId, (held.get(s.productId) || 0) + Number(s.quantity))
  cacheStock(
    shopId,
    products.map((p) => {
      const q = held.get(p.id)
      if (!q) return p
      const left = Number(p.quantity_on_hand) - q
      return { ...p, quantity_on_hand: Math.max(0, left), status: left <= 0 ? 'sold' : p.status }
    }),
  )
}
export function stockCacheDate(shopId: string) {
  return localStorage.getItem(stockKey(shopId) + ':at')
}

function assertOfflineStock(shopId: string, productId: string, quantity: number) {
  const p = cachedStock<StockEntry>(shopId).find((x) => x.id === productId)
  if (!p)
    throw new Error(
      'Produit absent du stock hors connexion. Reconnectez-vous pour actualiser le stock.',
    )
  if (Number(p.quantity_on_hand) < quantity)
    throw new Error('Stock hors connexion insuffisant pour cette vente.')
}
function reserveOfflineStock(shopId: string, productId: string, quantity: number) {
  const rows = cachedStock<StockEntry>(shopId),
    next = rows.map((p) =>
      p.id === productId
        ? {
            ...p,
            quantity_on_hand: Math.max(0, Number(p.quantity_on_hand) - quantity),
            status: Number(p.quantity_on_hand) - quantity <= 0 ? 'sold' : p.status,
          }
        : p,
    )
  cacheStock(shopId, next)
}

function restoreOfflineStock(shopId: string, productId: string, quantity: number) {
  const rows = cachedStock<StockEntry>(shopId)
  cacheStock(
    shopId,
    rows.map((p) =>
      p.id === productId
        ? { ...p, quantity_on_hand: Number(p.quantity_on_hand) + quantity, status: 'active' }
        : p,
    ),
  )
}
