// Service worker state shared with the interface: "new version available" prompt and private
// caches. The registration itself lives in pwaRegister.ts (web only, loaded by main.tsx).
import { useSyncExternalStore } from 'react'
import { flushOfflineStore } from './offline'

export type AppUpdateState = {
  /** A new version is installed and waits for a reload. */
  needRefresh: boolean
  /** The application is cached: it now opens without network. */
  offlineReady: boolean
}
let state: AppUpdateState = { needRefresh: false, offlineReady: false }
const listeners = new Set<() => void>()
let applyUpdate: (() => Promise<void>) | null = null

/** Name of the service worker cache of product photos (cleared on sign-out). */
export const PRODUCT_IMAGE_CACHE = 'covi-product-images'

/** Used by pwaRegister.ts. Also dispatches a `covi-app-update` event (detail: the new state). */
export function setAppUpdateState(patch: Partial<AppUpdateState>) {
  state = { ...state, ...patch }
  for (const listener of listeners) listener()
  window.dispatchEvent(new CustomEvent<AppUpdateState>('covi-app-update', { detail: state }))
}
/** Used by pwaRegister.ts: activates the waiting service worker and reloads the page. */
export function setAppUpdateHandler(handler: () => Promise<void>) {
  applyUpdate = handler
}
export const getAppUpdateState = () => state
export function subscribeAppUpdate(listener: () => void) {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}
/** Installs the new version: waits for the offline writes in progress, then reloads. */
export async function applyAppUpdate() {
  await flushOfflineStore()
  if (applyUpdate) await applyUpdate()
  else window.location.reload()
}
/** Hides the prompt until the next update is found (the new version is used at the next launch). */
export function dismissAppUpdate() {
  setAppUpdateState({ needRefresh: false })
}
/**
 * Update prompt state for the interface, e.g.
 * `const { needRefresh, reload, dismiss } = useAppUpdate()`.
 */
export function useAppUpdate() {
  const current = useSyncExternalStore(subscribeAppUpdate, getAppUpdateState, getAppUpdateState)
  return { ...current, reload: applyAppUpdate, dismiss: dismissAppUpdate }
}

/** Removes cached private data of the signed-out account (product photos). */
export async function clearPrivateCaches() {
  try {
    if (typeof caches !== 'undefined') await caches.delete(PRODUCT_IMAGE_CACHE)
  } catch {
    // ignored: Cache API unavailable
  }
}
