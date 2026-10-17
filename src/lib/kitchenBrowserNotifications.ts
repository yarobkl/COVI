import { supabase } from './supabase'

export type KitchenAlertMode = 'push' | 'browser' | 'unavailable'
const key = import.meta.env.VITE_COVI_KITCHEN_VAPID_PUBLIC_KEY ?? ''

// Convert standard VAPID base64url public key without exposing private credentials.
function vapidPublicKey(source: string): Uint8Array<ArrayBuffer> {
  const padded = source.replace(/-/g, '+').replace(/_/g, '/')
  const raw = atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, '='))
  const bytes = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i)
  if (bytes.length !== 65 || bytes[0] !== 4) throw Error('Clé publique Web Push invalide')
  return bytes
}

const workerScope = '/kitchen-alerts/'
const workerUrl = '/restaurant-kitchen-worker.js'

async function kitchenWorker() {
  return navigator.serviceWorker.register(workerUrl, { scope: workerScope })
}

/** Browser requires a user gesture for permission. Push registration fails closed. */
export async function requestKitchenBrowserAlerts(shopId: string): Promise<KitchenAlertMode> {
  if (
    !window.isSecureContext ||
    typeof Notification === 'undefined' ||
    !('serviceWorker' in navigator)
  )
    return 'unavailable'
  try {
    const permission = await Notification.requestPermission()
    if (permission !== 'granted') return 'unavailable'
    const registration = await kitchenWorker()
    if (!key || !('pushManager' in registration)) return 'browser'
    const existing = await registration.pushManager.getSubscription()
    const subscription =
      existing ??
      (await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: vapidPublicKey(key),
      }))
    const data = subscription.toJSON()
    if (!data.endpoint || !data.keys?.p256dh || !data.keys.auth) throw Error('Abonnement incomplet')
    const { data: registered, error } = await supabase.rpc('restaurant_kitchen_push_register', {
      p_shop: shopId,
      p_endpoint: data.endpoint,
      p_p256dh: data.keys.p256dh,
      p_auth: data.keys.auth,
    })
    if (error || !registered) {
      // A newly created subscription was not accepted by server; no false success.
      if (!existing) await subscription.unsubscribe()
      return 'browser'
    }
    return 'push'
  } catch {
    return 'browser'
  }
}

/** Logout and employee opt-out must revoke this device's subscription. */
export async function revokeKitchenBrowserAlerts(shopId: string): Promise<boolean> {
  if (!('serviceWorker' in navigator)) return true
  const registration = await navigator.serviceWorker.getRegistration(workerScope)
  const subscription = await registration?.pushManager?.getSubscription()
  if (!subscription) return true
  let removed = false
  try {
    const { error } = await supabase.rpc('restaurant_kitchen_push_unregister', {
      p_shop: shopId,
      p_endpoint: subscription.endpoint,
    })
    removed = !error
  } catch {
    /* offline: push provider unsubscribe still prevents future delivery */
  }
  try {
    await subscription.unsubscribe()
  } catch {
    return false
  }
  return removed
}

export async function showKitchenBrowserAlert(count: number) {
  if (
    !Number.isInteger(count) ||
    count < 1 ||
    typeof Notification === 'undefined' ||
    Notification.permission !== 'granted' ||
    !('serviceWorker' in navigator)
  )
    return
  try {
    const registration = await navigator.serviceWorker.getRegistration(workerScope)
    if (!registration) return
    await registration.showNotification('COVI — Nouvelle préparation', {
      body:
        count === 1
          ? 'Un nouvel article attend la cuisine.'
          : `${count} nouveaux articles attendent la cuisine.`,
      icon: '/icon-192.png',
      tag: 'covi-restaurant-kitchen',
      silent: false,
    })
  } catch {
    // Local browser notifications are best-effort; the server queue remains primary.
  }
}
