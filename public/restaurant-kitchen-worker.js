self.addEventListener('push', (event) => {
  event.waitUntil(
    self.registration.showNotification('COVI — Nouvelle préparation', {
      body: 'De nouvelles préparations attendent la cuisine.',
      icon: '/icon-192.png',
      tag: 'covi-restaurant-kitchen',
      renotify: false,
      data: { path: '/' },
    }),
  )
})
// Dedicated kitchen browser-notification worker.
// It never intercepts HTTP requests, and does not store sensitive data.
// Browser Push triggers a generic visible notification; details are fetched only
// after the user signs in and opens the private Kitchen screen.
self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(async (windows) => {
      for (const client of windows) {
        if (new URL(client.url).origin === self.location.origin && 'focus' in client) {
          return client.focus()
        }
      }
      return self.clients.openWindow('/')
    }),
  )
})
