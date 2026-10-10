// Offline data of the till: queue of sales recorded without network, sales refused by the server,
// cached stock and last loaded shop. Stored in IndexedDB once `initOfflineStore()` has run (with a
// synchronous in-memory mirror, so the public reads below stay synchronous), in localStorage
// before that or when IndexedDB is unavailable.
//
// Keep this module's imports to './idb' (and `await import('./covi')`): tests/offline.mjs loads it
// from the sources with Node's type stripping.
import { openOfflineDb, type OfflineDb, type WriteOp } from './idb'

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

/**
 * Thrown when a sale cannot be sent *yet* (no valid session, server unreachable…): the sale stays
 * queued and is retried, it is never moved to the refused sales.
 */
export class RetryLaterError extends Error {
  retryable = true
}
// Network failures (Chrome "Failed to fetch", Firefox "NetworkError…", Safari "Load failed"),
// timeouts, expired or missing JWT, and gateway errors are temporary: the sale is kept and retried.
// Business refusals raised by record_sale ("Insufficient stock", "Product unavailable"…) are not.
const RETRYABLE =
  /fetch|network|offline|load failed|timeout|timed out|abort|jwt|token|unauthori[sz]ed|\b401\b|not authenticated|service unavailable|bad gateway|gateway time|\b50[234]\b/i
/** Whether a failed send should be retried later (true) or is a definitive refusal (false). */
export function isRetryableSyncError(e: unknown) {
  if (e instanceof TypeError) return true
  if ((e as { retryable?: unknown } | null | undefined)?.retryable === true) return true
  const message = String(errorMessage(e) ?? e ?? '')
  const code = String((e as { code?: unknown } | null | undefined)?.code ?? '')
  // A shop ownership / SQL permission refusal must not be retried forever.
  // A missing or expired session can be retried after authentication is restored.
  if (/shop not found|permission denied/i.test(message)) return false
  if (code === '42501' || /42501/.test(message)) {
    return /authentication required|jwt|token|not authenticated/i.test(message)
  }
  return RETRYABLE.test(message)
}

/** Rejects with a retryable error when `promise` takes longer than `ms` (the work itself goes on). */
export function withTimeout<T>(promise: Promise<T>, ms: number, label = 'Délai dépassé (timeout)') {
  let timer: ReturnType<typeof setTimeout> | undefined
  return Promise.race([
    promise,
    new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new RetryLaterError(label)), ms)
    }),
  ]).finally(() => clearTimeout(timer))
}
// A sale attempted online waits at most this long before being queued (same operation id, so a
// late success on the server is not recorded twice); a background send waits a bit longer.
const SALE_TIMEOUT_MS = 10000,
  SYNC_TIMEOUT_MS = 20000

// ---------------------------------------------------------------------------------------------
// Storage. localStorage keys (v1/v2) are the historical format, still used as fallback and
// migrated into IndexedDB by initOfflineStore().
const KEY = 'covi:pending-sales:v1'
const LEGACY_REJECTED_KEY = 'covi:rejected-sales:v1'
const REJECTED_KEY = 'covi:rejected-sales:v2'
const STOCK_PREFIX = 'covi:stock:'
const KV_PREFIX = 'covi:kv:'
const KV_LEGACY_COUNT = 'legacyRejectedCount'
const stockKv = (shopId: string) => 'stock:' + shopId
type StockCache = { rows: unknown[]; at: string | null }

const ls = {
  get(key: string) {
    try {
      return localStorage.getItem(key)
    } catch {
      return null
    }
  },
  set(key: string, value: string) {
    localStorage.setItem(key, value)
  },
  remove(key: string) {
    try {
      localStorage.removeItem(key)
    } catch {
      // ignored: storage disabled
    }
  },
  keys(): string[] {
    try {
      const out: string[] = []
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i)
        if (key !== null) out.push(key)
      }
      return out
    } catch {
      return []
    }
  },
  json<T>(key: string, fallback: T): T {
    try {
      const raw = ls.get(key)
      return raw === null ? fallback : (JSON.parse(raw) ?? fallback)
    } catch {
      return fallback
    }
  },
}
const arrayOf = <T>(value: unknown): T[] => (Array.isArray(value) ? (value as T[]) : [])

/** IndexedDB connection once initOfflineStore() succeeded; `null` means localStorage mode. */
let db: OfflineDb | null = null
// In-memory mirror of IndexedDB (IndexedDB mode only). Pending sales keep their creation order.
let pendingMirror = new Map<string, PendingSale>()
let rejectedMirror = new Map<string, RejectedSale>()
let kvMirror = new Map<string, unknown>()
/** Bumped by each local change of the mirror, so that a reload racing with it is redone. */
let mirrorVersion = 0
const inflight = new Set<Promise<unknown>>()
let channel: BroadcastChannel | null = null

function track<T>(promise: Promise<T>) {
  inflight.add(promise)
  void promise.then(
    () => inflight.delete(promise),
    () => inflight.delete(promise),
  )
  return promise
}
/** Applies `ops` to IndexedDB and tells the other tabs; rejects when the transaction fails. */
function persist(ops: WriteOp[], strict = false) {
  const target = db
  if (!target) return Promise.resolve()
  let written: Promise<void>
  try {
    written = target.write(ops, strict)
  } catch (e) {
    written = Promise.reject(e)
  }
  return track(written.then(() => channel?.postMessage('changed')))
}
/** Same as persist() for non-critical writes: failures are logged, never thrown. */
function persistQuietly(ops: WriteOp[]) {
  return persist(ops).catch((e) => console.warn('COVI : écriture hors connexion échouée', e))
}

function readLegacyPending() {
  return arrayOf<PendingSale>(ls.json(KEY, []))
}
function writeLegacyPending(x: PendingSale[]) {
  ls.set(KEY, JSON.stringify(x))
}
/** Removes a sale from the localStorage queue (emergency copy or not yet migrated). */
function scrubLegacyPending(id: string) {
  try {
    const rows = readLegacyPending()
    if (rows.some((x) => x.id === id)) writeLegacyPending(rows.filter((x) => x.id !== id))
  } catch {
    // ignored: the copy is re-imported later and resent with its operation id (idempotent)
  }
}

const sortByCreation = (x: PendingSale[]) =>
  [...x].sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)))
function listPending(): PendingSale[] {
  return db ? [...pendingMirror.values()] : readLegacyPending()
}
function findPending(id: string) {
  return db ? pendingMirror.get(id) : readLegacyPending().find((x) => x.id === id)
}
/** Saves a queued sale (critical write: localStorage copy if IndexedDB fails, throws if both do). */
function putPending(x: PendingSale): Promise<void> {
  if (!db) {
    try {
      const rows = readLegacyPending()
      const i = rows.findIndex((r) => r.id === x.id)
      writeLegacyPending(i < 0 ? [...rows, x] : rows.map((r) => (r.id === x.id ? x : r)))
      return Promise.resolve()
    } catch (e) {
      return Promise.reject(e)
    }
  }
  pendingMirror.set(x.id, x)
  mirrorVersion++
  return persist([{ store: 'pending', type: 'put', value: x }], true).catch((e) => {
    console.warn('COVI : IndexedDB indisponible, vente copiée dans localStorage', e)
    const rows = readLegacyPending().filter((r) => r.id !== x.id)
    writeLegacyPending([...rows, x]) // throws when localStorage is full too
  })
}
function deletePending(id: string): Promise<void> {
  if (!db) {
    try {
      writeLegacyPending(readLegacyPending().filter((x) => x.id !== id))
    } catch {
      // ignored: resent later with the same operation id (idempotent)
    }
    return Promise.resolve()
  }
  pendingMirror.delete(id)
  mirrorVersion++
  scrubLegacyPending(id)
  return persistQuietly([{ store: 'pending', type: 'delete', key: id }])
}
/** Moves a sale from the queue to the refused sales in one transaction. */
function rejectPending(x: RejectedSale): Promise<void> {
  if (!db) {
    try {
      ls.set(REJECTED_KEY, JSON.stringify([...readLegacyRejected(), x]))
      writeLegacyPending(readLegacyPending().filter((r) => r.id !== x.id))
    } catch (e) {
      console.warn('COVI : vente refusée non enregistrée', e)
    }
    return Promise.resolve()
  }
  pendingMirror.delete(x.id)
  rejectedMirror.set(x.id, x)
  mirrorVersion++
  scrubLegacyPending(x.id)
  return persistQuietly([
    { store: 'pending', type: 'delete', key: x.id },
    { store: 'rejected', type: 'put', value: x },
  ])
}
function readLegacyRejected() {
  return arrayOf<RejectedSale>(ls.json(REJECTED_KEY, []))
}
function listRejected(): RejectedSale[] {
  return db ? [...rejectedMirror.values()] : readLegacyRejected()
}
function putRejected(rows: RejectedSale[]) {
  if (!db) {
    const byId = new Map(rows.map((x) => [x.id, x]))
    try {
      ls.set(REJECTED_KEY, JSON.stringify(readLegacyRejected().map((x) => byId.get(x.id) ?? x)))
    } catch (e) {
      console.warn('COVI : ventes refusées non mises à jour', e)
    }
    return Promise.resolve()
  }
  for (const x of rows) rejectedMirror.set(x.id, x)
  mirrorVersion++
  return persistQuietly(rows.map((value) => ({ store: 'rejected', type: 'put', value })))
}
function kvGet(key: string): unknown {
  if (db) return kvMirror.get(key)
  if (key.startsWith('stock:')) {
    const shopId = key.slice('stock:'.length),
      raw = ls.get(STOCK_PREFIX + shopId)
    if (raw === null) return undefined
    return {
      rows: arrayOf(ls.json(STOCK_PREFIX + shopId, [])),
      at: ls.get(STOCK_PREFIX + shopId + ':at'),
    }
  }
  if (key === KV_LEGACY_COUNT) return Number(ls.get(LEGACY_REJECTED_KEY) || 0)
  return ls.json<unknown>(KV_PREFIX + key, undefined)
}
function kvPut(key: string, value: unknown) {
  if (!db) {
    try {
      if (key.startsWith('stock:')) {
        const shopId = key.slice('stock:'.length),
          entry = value as StockCache
        ls.set(STOCK_PREFIX + shopId, JSON.stringify(entry.rows))
        if (entry.at) ls.set(STOCK_PREFIX + shopId + ':at', entry.at)
      } else if (key === KV_LEGACY_COUNT) {
        if (value) ls.set(LEGACY_REJECTED_KEY, String(value))
        else ls.remove(LEGACY_REJECTED_KEY)
      } else ls.set(KV_PREFIX + key, JSON.stringify(value))
    } catch (e) {
      console.warn('COVI : cache local non enregistré', e)
    }
    return Promise.resolve()
  }
  kvMirror.set(key, value)
  mirrorVersion++
  return persistQuietly([{ store: 'kv', type: 'put', key, value }])
}

/** Copies the localStorage data (v1/v2) into IndexedDB, then removes the copied keys. */
async function migrateLegacy(target: OfflineDb, snapshot: Map<string, unknown>) {
  const pendingRaw = ls.get(KEY),
    rejectedRaw = ls.get(REJECTED_KEY),
    countRaw = ls.get(LEGACY_REJECTED_KEY),
    keys = ls.keys(),
    stockKeys = keys.filter((k) => k.startsWith(STOCK_PREFIX) && !k.endsWith(':at')),
    kvKeys = keys.filter((k) => k.startsWith(KV_PREFIX))
  const nothing = pendingRaw === null && rejectedRaw === null && countRaw === null
  if (nothing && !stockKeys.length && !kvKeys.length) return
  const ops: WriteOp[] = []
  // Existing IndexedDB records win (they may carry a newer attempt count): putIfAbsent.
  for (const x of arrayOf<PendingSale>(ls.json(KEY, []))) {
    if (!x || typeof x !== 'object') continue
    const sale = typeof x.id === 'string' && x.id ? x : { ...x, id: crypto.randomUUID() }
    ops.push({ store: 'pending', type: 'putIfAbsent', key: sale.id, value: sale })
  }
  for (const x of arrayOf<RejectedSale>(ls.json(REJECTED_KEY, [])))
    if (x && typeof x.id === 'string')
      ops.push({ store: 'rejected', type: 'putIfAbsent', key: x.id, value: x })
  if (Number(countRaw))
    ops.push({
      store: 'kv',
      type: 'put',
      key: KV_LEGACY_COUNT,
      value: Number(snapshot.get(KV_LEGACY_COUNT) || 0) + Number(countRaw),
    })
  const stockRaw = new Map<string, [string | null, string | null]>()
  for (const key of stockKeys) {
    const shopId = key.slice(STOCK_PREFIX.length),
      at = ls.get(key + ':at'),
      current = snapshot.get(stockKv(shopId)) as StockCache | undefined
    stockRaw.set(key, [ls.get(key), at])
    if (current && (!at || (current.at && current.at >= at))) continue
    ops.push({
      store: 'kv',
      type: 'put',
      key: stockKv(shopId),
      value: { rows: arrayOf(ls.json(key, [])), at },
    })
  }
  const kvRaw = new Map(kvKeys.map((k) => [k, ls.get(k)]))
  for (const key of kvKeys)
    ops.push({
      store: 'kv',
      type: 'putIfAbsent',
      key: key.slice(KV_PREFIX.length),
      value: ls.json(key, null),
    })
  await target.write(ops, true)
  // Only remove what was copied: a key changed meanwhile (another tab) is migrated next time.
  if (pendingRaw !== null && ls.get(KEY) === pendingRaw) ls.remove(KEY)
  if (rejectedRaw !== null && ls.get(REJECTED_KEY) === rejectedRaw) ls.remove(REJECTED_KEY)
  if (countRaw !== null && ls.get(LEGACY_REJECTED_KEY) === countRaw) ls.remove(LEGACY_REJECTED_KEY)
  for (const [key, [rows, at]] of stockRaw)
    if (ls.get(key) === rows && ls.get(key + ':at') === at) {
      ls.remove(key)
      ls.remove(key + ':at')
    }
  for (const [key, raw] of kvRaw) if (ls.get(key) === raw) ls.remove(key)
}
const hasLegacyData = () =>
  ls.get(KEY) !== null || ls.get(REJECTED_KEY) !== null || ls.get(LEGACY_REJECTED_KEY) !== null

/** Reads IndexedDB (plus what is still only in localStorage) into the mirror. */
async function loadMirror(target: OfflineDb) {
  for (let attempt = 0; ; attempt++) {
    const version = mirrorVersion
    const snap = await target.readAll()
    // A local write happened during the read: its record may be missing from the snapshot.
    if (version !== mirrorVersion && attempt < 5) continue
    const pending = new Map<string, PendingSale>(),
      rejected = new Map<string, RejectedSale>(),
      kv = new Map<string, unknown>(snap.kv)
    for (const x of sortByCreation([
      ...arrayOf<PendingSale>(snap.pending),
      ...readLegacyPending().filter((x) => x && typeof x.id === 'string'),
    ]))
      if (!pending.has(x.id)) pending.set(x.id, x)
    for (const x of [...arrayOf<RejectedSale>(snap.rejected), ...readLegacyRejected()])
      if (x && typeof x.id === 'string' && !rejected.has(x.id)) rejected.set(x.id, x)
    const legacyCount = Number(ls.get(LEGACY_REJECTED_KEY) || 0)
    if (legacyCount) kv.set(KV_LEGACY_COUNT, Number(kv.get(KV_LEGACY_COUNT) || 0) + legacyCount)
    for (const key of ls.keys())
      if (key.startsWith(STOCK_PREFIX) && !key.endsWith(':at')) {
        const shopId = key.slice(STOCK_PREFIX.length)
        if (!kv.has(stockKv(shopId)))
          kv.set(stockKv(shopId), { rows: arrayOf(ls.json(key, [])), at: ls.get(key + ':at') })
      }
    pendingMirror = pending
    rejectedMirror = rejected
    kvMirror = kv
    return
  }
}

let refreshing: Promise<void> | null = null,
  refreshAgain = false
/** Re-reads the store (another tab changed it, or localStorage still holds legacy data). */
function refreshFromStorage(): Promise<void> {
  const target = db
  if (!target) return Promise.resolve()
  if (refreshing) {
    refreshAgain = true
    return refreshing
  }
  refreshing = (async () => {
    do {
      refreshAgain = false
      try {
        if (hasLegacyData()) await migrateLegacy(target, new Map((await target.readAll()).kv))
      } catch (e) {
        console.warn('COVI : migration hors connexion reportée', e)
      }
      await loadMirror(target)
    } while (refreshAgain)
  })().finally(() => {
    refreshing = null
  })
  return refreshing.then(() => {
    window.dispatchEvent(new Event('covi-sync'))
  })
}

let initPromise: Promise<void> | null = null
/**
 * Opens the IndexedDB store, migrates the localStorage data (no loss: copied records are removed
 * from localStorage only after the transaction is committed), loads the in-memory mirror and asks
 * the browser to keep the storage (navigator.storage.persist). Call it before the first render.
 * Never rejects: when IndexedDB is unavailable, the localStorage storage is kept.
 */
export function initOfflineStore(): Promise<void> {
  initPromise ??= (async () => {
    const opened = await openOfflineDb()
    if (opened) {
      try {
        const snapshot = new Map((await opened.readAll()).kv)
        try {
          await migrateLegacy(opened, snapshot)
        } catch (e) {
          // localStorage data stays where it is; loadMirror() still reads it.
          console.warn('COVI : migration vers IndexedDB reportée', e)
        }
        await loadMirror(opened)
        db = opened
        if (typeof BroadcastChannel !== 'undefined') {
          channel = new BroadcastChannel('covi-offline')
          // Node (tests): do not keep the process alive.
          ;(channel as unknown as { unref?: () => void }).unref?.()
          channel.onmessage = () =>
            void refreshFromStorage().catch((e) =>
              console.warn('COVI : relecture hors connexion impossible', e),
            )
        }
      } catch (e) {
        console.warn('COVI : IndexedDB illisible, stockage local conservé', e)
        opened.close()
      }
    }
    void requestPersistentStorage()
    if (typeof window !== 'undefined') window.dispatchEvent(new Event('covi-sync'))
  })()
  return initPromise
}
/** Closes the store, back to localStorage mode (tests: simulates the end of a page). */
export function closeOfflineStore() {
  channel?.close()
  channel = null
  db?.close()
  db = null
  initPromise = null
}
/** Resolves once every write started so far has been committed (or has failed). */
export async function flushOfflineStore() {
  await Promise.allSettled([...inflight])
}
/** Where the offline data currently lives. */
export const offlineStorageMode = (): 'indexeddb' | 'localstorage' =>
  db ? 'indexeddb' : 'localstorage'
/** Storage state for a settings or diagnostics screen. */
export async function offlineStorageStatus() {
  const storage = typeof navigator !== 'undefined' ? navigator.storage : undefined
  const [persisted, estimate] = await Promise.all([
    storage?.persisted?.().catch(() => false) ?? false,
    storage?.estimate?.().catch(() => undefined),
  ])
  return {
    mode: offlineStorageMode(),
    persisted,
    usage: estimate?.usage ?? null,
    quota: estimate?.quota ?? null,
  }
}
// Asked once: the browser may then keep this data under storage pressure (Chrome grants it
// silently to installed or frequently used apps).
async function requestPersistentStorage() {
  try {
    const storage = navigator.storage
    if (!storage?.persist || !storage.persisted || (await storage.persisted())) return
    if (kvGet('persistRequested')) return
    await kvPut('persistRequested', true)
    await storage.persist()
  } catch {
    // ignored: optional
  }
}

/** Last shop loaded for an account, to open the till offline. */
export function cachedShop<T>(userId: string): T | null {
  return (kvGet('shop:' + userId) as T | undefined) ?? null
}
export function rememberShop<T>(userId: string, shop: T) {
  return kvPut('shop:' + userId, shop)
}

// ---------------------------------------------------------------------------------------------
// Each queued sale belongs to the account that recorded it and is only synced while that account is signed in. Entries queued before userId existed are synced by whoever is signed in.
let activeUser: string | null = null
const mine = (x: PendingSale) => !x.userId || x.userId === activeUser
export function setSyncUser(userId: string | null) {
  if (userId === activeUser) return
  activeUser = userId
  resetSyncBackoff()
  window.dispatchEvent(new Event('covi-sync'))
}
export const rejectedSales = () => listRejected().filter(mine)
export const rejectedSaleCount = () =>
  Number(kvGet(KV_LEGACY_COUNT) || 0) + rejectedSales().filter((x) => !x.dismissed).length
export function clearRejectedSaleCount() {
  void kvPut(KV_LEGACY_COUNT, 0)
  void putRejected(rejectedSales().map((x) => ({ ...x, dismissed: true })))
  window.dispatchEvent(new Event('covi-sync'))
}
export const pendingSales = () => listPending().filter(mine)
export const pendingCount = () => pendingSales().length

function enqueue(
  input: Omit<PendingSale, 'id' | 'createdAt' | 'attempts' | 'userId'> & { userId: string },
  operationId: string,
) {
  const x: PendingSale = {
    ...input,
    id: operationId,
    createdAt: new Date().toISOString(),
    attempts: 0,
  }
  const saved = putPending(x)
  reserveOfflineStock(input.shopId, input.productId, input.quantity)
  window.dispatchEvent(new Event('covi-sync'))
  registerBackgroundSync()
  return { sale: x, saved }
}
export function queueSale(
  input: Omit<PendingSale, 'id' | 'createdAt' | 'attempts' | 'userId'> & { userId: string },
  operationId: string = crypto.randomUUID(),
) {
  const { sale, saved } = enqueue(input, operationId)
  saved.catch((e) => console.error('COVI : vente hors connexion non enregistrée', e))
  return sale
}
// Background Sync (Chromium): the service worker wakes the open pages when the network is back,
// even if the tab is in the background. Optional: the triggers below work without it.
function registerBackgroundSync() {
  try {
    const sw = typeof navigator !== 'undefined' ? navigator.serviceWorker : undefined
    if (!sw?.getRegistration) return
    void sw
      .getRegistration()
      .then((r) =>
        (r as { sync?: { register: (tag: string) => Promise<void> } } | undefined)?.sync?.register(
          'covi-sync',
        ),
      )
      .catch(() => undefined)
  } catch {
    // ignored: optional
  }
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
/** Starts a synchronisation when there is something to send (no-op otherwise). */
export function requestSync() {
  if (navigator.onLine && activeUser && pendingCount() > 0) void syncPendingSales()
}
/**
 * The session is usable again (token refreshed, signed in, network back, app in the foreground):
 * cancels the backoff and sends the queue right away.
 */
export function resumeSync() {
  resetSyncBackoff()
  requestSync()
}
if (typeof window !== 'undefined') {
  window.addEventListener('online', resumeSync)
  if (typeof document !== 'undefined')
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') resumeSync()
    })
  if (typeof navigator !== 'undefined')
    navigator.serviceWorker?.addEventListener?.('message', (e: MessageEvent) => {
      if ((e.data as { type?: unknown } | null)?.type === 'covi-sync') resumeSync()
    })
}
type SyncResult = { synced: number; pending: number; rejected: number }
export async function syncPendingSales(): Promise<SyncResult> {
  const user = activeUser
  if (!navigator.onLine || syncInProgress || !user || Date.now() < retryAt)
    return { synced: 0, pending: pendingCount(), rejected: 0 }
  syncInProgress = true
  let synced = 0,
    rejected = 0,
    failed = false
  const run = async () => {
    if (db && hasLegacyData()) await refreshFromStorage()
    for (const item of listPending().filter(mine)) {
      if (activeUser !== user) break
      // Already sent by another tab, or removed meanwhile.
      if (!findPending(item.id)) continue
      let failure: unknown = null
      try {
        const { recordSale } = await import('./covi')
        await withTimeout(
          recordSale(
            item.shopId,
            item.productId,
            item.quantity,
            item.soldUnitPrice,
            item.paymentLabel,
            item.id,
          ),
          SYNC_TIMEOUT_MS,
        )
      } catch (e) {
        failure = e
      }
      if (failure === null) {
        await deletePending(item.id)
        synced++
        continue
      }
      const message = String(errorMessage(failure) || 'Erreur de synchronisation')
      if (isRetryableSyncError(failure)) {
        const current = findPending(item.id) ?? item
        await putPending({ ...current, attempts: current.attempts + 1, lastError: message }).catch(
          () => undefined,
        )
        failed = true
        break
      }
      await rejectPending({
        ...item,
        userId: item.userId ?? user,
        reason: message,
        rejectedAt: new Date().toISOString(),
      })
      restoreOfflineStock(item.shopId, item.productId, item.quantity)
      rejected++
    }
  }
  try {
    // Web Locks: a single tab sends the queue at a time (the server deduplicates anyway).
    const locks = (navigator as Partial<Navigator>).locks
    if (locks?.request)
      await locks.request('covi-sync-sales', { ifAvailable: true }, (lock) =>
        lock ? run() : undefined,
      )
    else await run()
  } catch (e) {
    // Unexpected (storage read failure…): the queue is untouched, try again later.
    console.warn('COVI : synchronisation interrompue', e)
    failed = true
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
    queue = async (checkStock: boolean) => {
      if (!userId)
        throw new Error('Session introuvable. Reconnectez-vous pour enregistrer cette vente.')
      if (checkStock) assertOfflineStock(input.shopId, input.productId, input.quantity)
      const { saved } = enqueue({ ...input, userId }, operationId)
      try {
        await saved
      } catch {
        // Neither IndexedDB nor localStorage accepted it: undo and tell the cashier.
        if (db) pendingMirror.delete(operationId)
        restoreOfflineStock(input.shopId, input.productId, input.quantity)
        window.dispatchEvent(new Event('covi-sync'))
        throw new Error(
          'Vente non enregistrée : la mémoire de l’appareil est pleine ou indisponible. Libérez de l’espace puis réessayez.',
        )
      }
      return { offline: true }
    }
  if (!navigator.onLine) return queue(true)
  try {
    const { recordSale } = await import('./covi')
    await withTimeout(
      recordSale(
        input.shopId,
        input.productId,
        input.quantity,
        input.soldUnitPrice,
        input.paymentLabel,
        operationId,
      ),
      SALE_TIMEOUT_MS,
    )
    return { offline: false }
  } catch (e) {
    if (!isRetryableSyncError(e)) throw e
    // The server may have recorded it before the connection dropped: queue it with the same
    // operation id (deduplicated by record_sale) and without the local stock check, so that the
    // cashier is never led to record it a second time.
    return queue(false)
  }
}

/** Fields of a cached product that the offline queue reads; other fields are kept as they are. */
type StockEntry = { id: string; quantity_on_hand: number; status: string }
export function cachedStock<T>(shopId: string): T[] {
  return arrayOf<T>((kvGet(stockKv(shopId)) as StockCache | undefined)?.rows)
}
export function cacheStock<T>(shopId: string, products: T[]) {
  void kvPut(stockKv(shopId), { rows: products, at: new Date().toISOString() })
}
// Server stock does not yet include queued offline sales: keep them reserved so a refresh cannot re-open sold pieces offline.
export function cacheServerStock<
  T extends { id: string; quantity_on_hand: number; status: string },
>(shopId: string, products: T[]) {
  const held = new Map<string, number>()
  for (const s of listPending())
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
  return (kvGet(stockKv(shopId)) as StockCache | undefined)?.at ?? null
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
