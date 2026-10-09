import { useEffect, useState } from 'react'
import {
  clearRejectedSaleCount,
  pendingCount,
  rejectedSaleCount,
  syncPendingSales,
} from '../lib/offline'
export function SyncStatus() {
  const [online, setOnline] = useState(navigator.onLine),
    [pending, setPending] = useState(pendingCount()),
    [rejected, setRejected] = useState(rejectedSaleCount())
  useEffect(() => {
    const update = () => {
      setOnline(navigator.onLine)
      setPending(pendingCount())
      setRejected(rejectedSaleCount())
      if (navigator.onLine && pendingCount() > 0)
        void syncPendingSales().then(() => setPending(pendingCount()))
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
  return (
    <div className={'sync ' + (!online || pending || rejected ? 'pending' : '')}>
      {!online ? (
        '● Hors connexion'
      ) : pending ? (
        '● ' + pending + ' vente' + (pending > 1 ? 's' : '') + ' à synchroniser'
      ) : rejected ? (
        <button
          type="button"
          onClick={clearRejectedSaleCount}
          title="Le stock local a été rétabli. Cliquez pour fermer."
        >
          ● {rejected} vente{rejected > 1 ? 's' : ''} refusée{rejected > 1 ? 's' : ''} · stock
          rétabli ×
        </button>
      ) : (
        '● Synchronisé'
      )}
    </div>
  )
}
