/// <reference types="vite-plugin-pwa/client" />
// Registers the service worker (web only: never in Tauri, whose files are local already).
import { registerSW } from 'virtual:pwa-register'
import { isTauriApp } from './desktopAuth'
import { setAppUpdateHandler, setAppUpdateState } from './pwa'

const UPDATE_CHECK_MS = 60 * 60 * 1000

export function registerServiceWorker() {
  if (isTauriApp() || !('serviceWorker' in navigator)) return
  const update = registerSW({
    immediate: true,
    onNeedRefresh: () => setAppUpdateState({ needRefresh: true }),
    onOfflineReady: () => setAppUpdateState({ offlineReady: true }),
    onRegisteredSW: (_url, registration) => {
      if (registration) watchForUpdates(registration)
    },
    onRegisterError: (e) => console.warn('COVI : service worker non enregistré', e),
  })
  setAppUpdateHandler(() => update(true))
}

// The browser only looks for a new service worker on navigation: the till stays open all day, so
// check at most hourly, when online and in the foreground.
function watchForUpdates(registration: ServiceWorkerRegistration) {
  let last = Date.now()
  const check = () => {
    if (!navigator.onLine || document.visibilityState !== 'visible') return
    if (Date.now() - last < UPDATE_CHECK_MS) return
    last = Date.now()
    void registration.update().catch(() => undefined)
  }
  document.addEventListener('visibilitychange', check)
  window.addEventListener('online', check)
  setInterval(check, UPDATE_CHECK_MS / 4)
}
