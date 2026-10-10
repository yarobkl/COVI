import { useEffect, useState } from 'react'
import { pendingCount, rejectedSaleCount, syncPendingSales } from '../../lib/offline'

export type SyncState = {
  /** The device has a network connection. */
  online: boolean
  /** Sales kept on this device, not sent yet. */
  pending: number
  /** Sales the account refused (stock restored on the device), not acknowledged yet. */
  rejected: number
}

/**
 * Network and offline-queue state; sends the waiting sales whenever the network comes back.
 * Mount it once (in the shell).
 */
export function useSyncState(): SyncState {
  const [state, setState] = useState<SyncState>(() => ({
    online: navigator.onLine,
    pending: pendingCount(),
    rejected: rejectedSaleCount(),
  }))
  useEffect(() => {
    const read = () =>
      setState({
        online: navigator.onLine,
        pending: pendingCount(),
        rejected: rejectedSaleCount(),
      })
    const update = () => {
      read()
      if (navigator.onLine && pendingCount() > 0) void syncPendingSales().then(read)
    }
    window.addEventListener('online', update)
    window.addEventListener('offline', update)
    window.addEventListener('covi-sync', update)
    update()
    return () => {
      window.removeEventListener('online', update)
      window.removeEventListener('offline', update)
      window.removeEventListener('covi-sync', update)
    }
  }, [])
  return state
}
