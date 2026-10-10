// Minimal IndexedDB layer for the offline data (no dependency). Every write of a call runs in a
// single transaction, so that it is applied entirely or not at all.
//
// Keep this module free of imports and of TypeScript-only runtime syntax (enums, parameter
// properties): tests/offline.mjs loads it with Node's type stripping.

export type StoreName = 'pending' | 'rejected' | 'kv'
/** Stores whose records carry their own key (`id`); `kv` uses explicit keys. */
const KEY_PATH_STORES: StoreName[] = ['pending', 'rejected']
export type WriteOp =
  | { store: StoreName; type: 'put'; value: unknown; key?: string }
  /** Writes `value` only when no record has this key yet (legacy migration). */
  | { store: StoreName; type: 'putIfAbsent'; value: unknown; key: string }
  | { store: StoreName; type: 'delete'; key: string }
export type Snapshot = {
  pending: unknown[]
  rejected: unknown[]
  kv: [string, unknown][]
}
export type OfflineDb = {
  /** Applies `ops` in one transaction; resolves once it is committed. */
  write: (ops: WriteOp[], strict?: boolean) => Promise<void>
  readAll: () => Promise<Snapshot>
  close: () => void
}

const DB_NAME = 'covi-offline',
  DB_VERSION = 1

const done = (tx: IDBTransaction) =>
  new Promise<void>((resolve, reject) => {
    tx.oncomplete = () => resolve()
    tx.onerror = () => reject(tx.error ?? new Error('Transaction IndexedDB refusée'))
    tx.onabort = () => reject(tx.error ?? new Error('Transaction IndexedDB annulée'))
  })

function wrap(db: IDBDatabase): OfflineDb {
  return {
    write(ops, strict = false) {
      if (!ops.length) return Promise.resolve()
      const names = [...new Set(ops.map((op) => op.store))]
      // `durability: 'strict'` (Chromium) waits for the disk flush before `complete`: used for sales.
      const tx = db.transaction(names, 'readwrite', { durability: strict ? 'strict' : 'default' })
      const completed = done(tx)
      for (const op of ops) {
        const store = tx.objectStore(op.store),
          explicitKey = KEY_PATH_STORES.includes(op.store) ? undefined : op.key
        if (op.type === 'delete') store.delete(op.key)
        else if (op.type === 'put') store.put(op.value, explicitKey)
        else {
          const existing = store.getKey(op.key)
          existing.onsuccess = () => {
            if (existing.result === undefined) store.put(op.value, explicitKey)
          }
        }
      }
      return completed
    },
    readAll() {
      let tx: IDBTransaction
      try {
        tx = db.transaction(['pending', 'rejected', 'kv'], 'readonly')
      } catch (e) {
        // Connection closed (another tab upgraded or deleted the database).
        return Promise.reject(e)
      }
      const completed = done(tx)
      const pending = tx.objectStore('pending').getAll(),
        rejected = tx.objectStore('rejected').getAll(),
        kvStore = tx.objectStore('kv'),
        keys = kvStore.getAllKeys(),
        values = kvStore.getAll()
      return completed.then(() => ({
        pending: pending.result,
        rejected: rejected.result,
        kv: (keys.result as string[]).map((key, i) => [key, values.result[i]] as [string, unknown]),
      }))
    },
    close: () => db.close(),
  }
}

/**
 * Opens the offline database, or resolves `null` when IndexedDB is missing, blocked or does not
 * answer within `timeoutMs` (some WebViews hang on the first open): callers then keep localStorage.
 */
export function openOfflineDb(timeoutMs = 4000): Promise<OfflineDb | null> {
  return new Promise((resolve) => {
    let settled = false
    const finish = (db: OfflineDb | null) => {
      if (settled) {
        db?.close()
        return
      }
      settled = true
      clearTimeout(timer)
      resolve(db)
    }
    const timer = setTimeout(() => finish(null), timeoutMs)
    try {
      if (typeof indexedDB === 'undefined') return finish(null)
      const request = indexedDB.open(DB_NAME, DB_VERSION)
      request.onupgradeneeded = () => {
        const db = request.result
        if (!db.objectStoreNames.contains('pending'))
          db.createObjectStore('pending', { keyPath: 'id' })
        if (!db.objectStoreNames.contains('rejected'))
          db.createObjectStore('rejected', { keyPath: 'id' })
        if (!db.objectStoreNames.contains('kv')) db.createObjectStore('kv')
      }
      request.onsuccess = () => {
        const db = request.result
        // Another tab running a newer version needs this connection closed to upgrade.
        db.onversionchange = () => db.close()
        finish(wrap(db))
      }
      request.onerror = () => finish(null)
      request.onblocked = () => finish(null)
    } catch {
      finish(null)
    }
  })
}

/** Deletes the offline database (tests only). */
export function deleteOfflineDb(): Promise<void> {
  return new Promise((resolve) => {
    const request = indexedDB.deleteDatabase(DB_NAME)
    request.onsuccess = request.onerror = request.onblocked = () => resolve()
  })
}
