// Dedicated kitchen browser-notification worker.
// It does not intercept requests and has NO background push subscription.
// It only handles click-to-focus for user-approved app-generated notices.
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
