import { useEffect, useRef, useState, type ReactNode } from 'react'
import { Button, Notice } from '../../components/ui'
import type { Shop } from '../../lib/types'
import { useSyncState } from '../sync/useSyncState'
import { useCounterMode } from './useCounterMode'
import { useTillSession } from './useTillSession'

/**
 * A leftover owner-authenticated shared till is NOT a safe cashier session. End that
 * owner session before anyone can use this browser as a cashier. No privileged app
 * pages or sale buttons are mounted while a legacy counter flag/token is present.
 */
function RetireLegacyCounter({ signOut }: { signOut: () => Promise<void> }) {
  const { pending } = useSyncState()
  const started = useRef(false)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const leave = async () => {
    if (pending > 0 || busy) return
    started.current = true
    setBusy(true)
    setError('')
    try {
      await signOut()
    } catch {
      setError('La déconnexion du responsable a échoué. Réessayez.')
      setBusy(false)
    }
  }

  // Fail closed for devices still carrying a shared till from the old preview.
  // Do not abandon an offline sale that has not been synchronized yet.
  useEffect(() => {
    if (pending === 0 && !started.current) {
      started.current = true
      void signOut().catch(() => {
        started.current = false
        setError('La déconnexion du responsable a échoué. Réessayez.')
      })
    }
  }, [pending, signOut])

  return (
    <main className="authshell">
      <section className="authcard" role="status">
        <h1>COVI</h1>
        <h2>Caisse sur appareil partagé</h2>
        <p>
          Pour protéger les données de la boutique, la caisse ne fonctionne plus sous le compte
          connecté du responsable. Le caissier doit se connecter avec son propre compte.
        </p>
        {pending > 0 ? (
          <Notice tone="danger">
            <p>
              {pending} vente(s) en attente de synchronisation. La session du responsable ne sera
              pas fermée avant leur envoi. Gardez la connexion active.
            </p>
          </Notice>
        ) : (
          <p>Déconnexion du responsable en cours. La page de connexion s’ouvrira ensuite.</p>
        )}
        {error && (
          <Notice tone="danger">
            <p>{error}</p>
          </Notice>
        )}
        <Button variant="primary" disabled={pending > 0 || busy} onClick={() => void leave()}>
          Réessayer la déconnexion
        </Button>
      </section>
    </main>
  )
}

export function CounterGate({
  shop,
  signOut,
  children,
}: {
  shop: Shop
  userId: string
  signOut: () => Promise<void>
  children: ReactNode
}) {
  const counter = useCounterMode(shop.id)
  const till = useTillSession(shop.id)
  if (counter || till) return <RetireLegacyCounter signOut={signOut} />
  return <>{children}</>
}
