import { useCallback, useEffect, useState } from 'react'
import {
  loadNotifications,
  markSeen,
  readSeen,
  type ShopNotification,
} from '../../lib/notifications'

/** Toutes les 2 minutes et au retour sur l'onglet : assez pour voir arriver une commande. */
const REFRESH_MS = 2 * 60 * 1000

/** Les alertes de la boutique, relues régulièrement ; une seule source pour les deux cloches. */
export function useShopNotifications(shopId: string) {
  const [items, setItems] = useState<ShopNotification[] | null>(null)
  const [failed, setFailed] = useState(false)
  const [seen, setSeen] = useState(() => readSeen(shopId))

  const refresh = useCallback(() => {
    if (!navigator.onLine) return
    loadNotifications(shopId)
      .then((list) => {
        setItems(list)
        setFailed(false)
      })
      .catch(() => setFailed(true))
  }, [shopId])

  useEffect(() => {
    refresh()
    const timer = window.setInterval(refresh, REFRESH_MS)
    const onVisible = () => document.visibilityState === 'visible' && refresh()
    document.addEventListener('visibilitychange', onVisible)
    window.addEventListener('online', refresh)
    return () => {
      window.clearInterval(timer)
      document.removeEventListener('visibilitychange', onVisible)
      window.removeEventListener('online', refresh)
    }
  }, [refresh])

  const markAllSeen = useCallback(() => {
    const ids = (items ?? []).map((n) => n.id)
    markSeen(shopId, ids)
    setSeen(new Set(ids))
  }, [items, shopId])

  return { items, failed, seen, refresh, markAllSeen }
}

export type ShopNotificationsState = ReturnType<typeof useShopNotifications>
