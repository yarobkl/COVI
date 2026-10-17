import { useCallback, useEffect, useRef, useState } from 'react'
import { Button, Notice, Sheet } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import {
  newlyArrivedKitchenCount,
  readKitchenInbox,
  type KitchenInbox,
} from '../../lib/kitchenInbox'
import {
  requestKitchenBrowserAlerts,
  revokeKitchenBrowserAlerts,
  showKitchenBrowserAlert,
  type KitchenAlertMode,
} from '../../lib/kitchenBrowserNotifications'

/** Independent kitchen event inbox. Backlog is kept on the server per staff account. */
export function RestaurantKitchenInbox({ shopId }: { shopId: string }) {
  const [inbox, setInbox] = useState<KitchenInbox | null>(null)
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [browserMode, setBrowserMode] = useState<KitchenAlertMode>('unavailable')
  const maxArrived = useRef<string | null>(null)
  const permissionEnabled = useRef(false)

  const refresh = useCallback(async () => {
    const { data, error: fault } = await supabase.rpc('restaurant_kitchen_inbox', {
      p_shop: shopId,
    })
    if (fault) throw fault
    return readKitchenInbox(data)
  }, [shopId])

  useEffect(() => {
    let live = true
    maxArrived.current = null
    let inFlight = false
    async function poll() {
      if (!navigator.onLine || inFlight) return
      inFlight = true
      try {
        const updated = await refresh()
        if (!live) return
        const { newest, count } = newlyArrivedKitchenCount(maxArrived.current, updated)
        maxArrived.current = newest
        setInbox(updated)
        setError('')
        if (permissionEnabled.current && document.visibilityState === 'hidden' && count > 0)
          void showKitchenBrowserAlert(count)
      } catch {
        if (live) {
          setError(
            'Impossible de récupérer les préparations : vérifiez la connexion et les droits.',
          )
          setInbox(null)
        }
      } finally {
        inFlight = false
      }
    }
    void Promise.resolve().then(poll)
    const interval = window.setInterval(() => void poll(), 10000)
    const onReturn = () => void poll()
    document.addEventListener('visibilitychange', onReturn)
    window.addEventListener('online', onReturn)
    return () => {
      live = false
      window.clearInterval(interval)
      document.removeEventListener('visibilitychange', onReturn)
      window.removeEventListener('online', onReturn)
    }
  }, [refresh])

  async function enableNotifications() {
    setError('')
    const mode = await requestKitchenBrowserAlerts(shopId)
    permissionEnabled.current = mode === 'browser'
    setBrowserMode(mode)
    setMessage(
      mode === 'push'
        ? 'Web Push enregistré pour ce restaurant et cet appareil. La livraison dépend encore de l’activation du serveur d’envoi.'
        : mode === 'browser'
          ? 'Alertes locales autorisées pendant que COVI peut synchroniser. Web Push non configuré ou indisponible.'
          : 'Permission refusée ou navigateur incompatible. La file Cuisine reste disponible.',
    )
  }
  async function markRead() {
    if (!inbox?.events.length || busy) return
    const through = inbox.events[inbox.events.length - 1].id
    setBusy(true)
    setError('')
    try {
      const { data, error: fault } = await supabase.rpc('restaurant_kitchen_acknowledge', {
        p_shop: shopId,
        p_through: through,
      })
      if (fault || typeof data !== 'string' || BigInt(data) < BigInt(through))
        throw fault ?? Error('Accusé de lecture non confirmé.')
      const fresh = await refresh()
      // Without a request to serve a line, it remains in the kitchen list of work.
      maxArrived.current = newlyArrivedKitchenCount(maxArrived.current, fresh).newest
      setInbox(fresh)
      setMessage('Ces préparations ont été vues. Les plats restent à servir.')
    } catch {
      setError('Accusé de lecture non vérifié. Réactualisez avant de recommencer.')
    } finally {
      setBusy(false)
    }
  }
  const rows = inbox?.events ?? []
  return (
    <Sheet aria-label="Notifications des préparations en cuisine">
      <h2 className="section-title">Nouvelles préparations</h2>
      <p className="muted">
        Les événements non lus sont conservés dans le restaurant, même après une coupure réseau.
        Seuls les plats et boissons encore à préparer apparaissent ici.
      </p>
      {error && (
        <Notice tone="danger">
          <p>{error}</p>
        </Notice>
      )}
      {message && (
        <Notice tone="calm">
          <p>{message}</p>
        </Notice>
      )}
      <Button onClick={() => void enableNotifications()} disabled={browserMode !== 'unavailable'}>
        {browserMode === 'push' ? 'Web Push activé sur cet appareil'
          : browserMode === 'browser' ? 'Alertes locales autorisées'
          : 'Autoriser les notifications Cuisine'}
      </Button>
      {browserMode === 'push' && <Button onClick={() => {
        void revokeKitchenBrowserAlerts(shopId).then(ok => {
          setBrowserMode('unavailable')
          setMessage(ok ? 'Notifications désactivées sur cet appareil.'
            : 'Appareil désabonné, mais serveur non vérifié : contactez le responsable si nécessaire.')
        })
      }}>Désactiver sur cet appareil</Button>}
      <p className="muted">
        En mode Web Push, les alertes peuvent atteindre une application fermée si le serveur d’envoi
        est activé et le système autorise les notifications. Sur iPhone, COVI doit être installée
        sur l’écran d’accueil. La réception n’est jamais garantie sans réseau.
      </p>
      {!inbox ? (
        <p role="status">Vérification des nouvelles commandes…</p>
      ) : rows.length === 0 ? (
        <p className="muted">Aucune nouvelle préparation non lue.</p>
      ) : (
        <>
          <ul className="team-invites">
            {rows.map((entry) => (
              <li key={entry.id}>
                <div>
                  <strong>
                    Table {entry.table} · {entry.quantity} × {entry.item}
                  </strong>
                  <p className="muted">
                    Commande {entry.orderReference ?? 'en cours'}
                    {' · '}
                    {new Date(entry.at).toLocaleTimeString('fr-FR')}
                  </p>
                </div>
              </li>
            ))}
          </ul>
          {inbox.more && (
            <Notice tone="calm">
              <p>
                D’autres préparations attendent dans la file. Confirmez la lecture de cette page
                pour récupérer les suivantes.
              </p>
            </Notice>
          )}
          <Button variant="primary" busy={busy} onClick={() => void markRead()}>
            J’ai vu ces {rows.length} préparation(s)
          </Button>
        </>
      )}
    </Sheet>
  )
}
