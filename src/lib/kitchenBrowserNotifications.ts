/**
 * Optional native browser notices while the COVI staff page can still poll.
 * No true remote Web Push delivery when the app is closed is promised here.
 */
export async function requestKitchenBrowserAlerts(): Promise<boolean> {
  if (!window.isSecureContext || typeof Notification === 'undefined' ||
      !('serviceWorker' in navigator)) return false
  try {
    const permission = await Notification.requestPermission()
    if (permission !== 'granted') return false
    await navigator.serviceWorker.register('/restaurant-kitchen-worker.js', {
      scope: '/kitchen-alerts/',
    })
    return true
  } catch {
    return false
  }
}

export async function showKitchenBrowserAlert(count: number) {
  if (!Number.isInteger(count) || count < 1 ||
      typeof Notification === 'undefined' ||
      Notification.permission !== 'granted' ||
      !('serviceWorker' in navigator)) return
  try {
    const registration = await navigator.serviceWorker.getRegistration('/kitchen-alerts/')
    if (!registration) return
    await registration.showNotification('COVI — Nouvelle préparation', {
      body: count === 1
        ? 'Un nouvel article attend la cuisine.'
        : `${count} nouveaux articles attendent la cuisine.`,
      icon: '/icon-192.png',
      tag: 'covi-restaurant-kitchen',
      silent: false,
    })
  } catch {
    // Native notifications are best-effort; the durable in-app queue is primary.
  }
}
