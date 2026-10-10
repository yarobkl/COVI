// Imported by the generated service worker (vite.config.ts, workbox.importScripts).
// Background Sync: when the network is back, wake the open COVI pages so that they send their
// queued sales (the queue and the session live in the page; the service worker never sends them).
self.addEventListener('sync', (event) => {
  if (event.tag !== 'covi-sync') return
  event.waitUntil(
    self.clients
      .matchAll({ type: 'window', includeUncontrolled: true })
      .then((clients) => clients.forEach((client) => client.postMessage({ type: 'covi-sync' }))),
  )
})
