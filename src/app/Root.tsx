import { lazy, Suspense, useEffect, useState } from 'react'
import '../styles/index.css'
import { AuthGate } from '../features/auth/AuthGate'
import { CounterGate } from '../features/team/CounterGate'
import { parsePublicHash } from '../lib/publicOrders'
import { App } from './App'

// The example shop is only opened on demand: kept out of the first download.
const DemoMode = lazy(() =>
  import('../features/demo/DemoMode').then((m) => ({ default: m.DemoMode })),
)

// Customer pages opened by a shop's QR code or WhatsApp / TikTok link: no account, no app shell.
const PublicOrderPage = lazy(() =>
  import('../features/orders/PublicOrderPage').then((m) => ({ default: m.PublicOrderPage })),
)
const PrivacyPage = lazy(() =>
  import('../features/legal/PrivacyPage').then((m) => ({ default: m.PrivacyPage })),
)
const PublicTrackingPage = lazy(() =>
  import('../features/orders/PublicTrackingPage').then((m) => ({ default: m.PublicTrackingPage })),
)

/** Pages publiques : commande, suivi et politique de confidentialité (lisible sans compte). */
const publicRoute = (hash: string) =>
  /^#\/confidentialite\/?$/.test(hash) ? ({ kind: 'privacy' } as const) : parsePublicHash(hash)

function usePublicRoute() {
  const [route, setRoute] = useState(() => publicRoute(window.location.hash))
  useEffect(() => {
    const sync = () => setRoute(publicRoute(window.location.hash))
    window.addEventListener('hashchange', sync)
    return () => window.removeEventListener('hashchange', sync)
  }, [])
  return route
}

// index.html has no <html lang>: screen readers must read French.
document.documentElement.lang = 'fr'

/** Switches between the simulation (no account needed) and the signed-in application. */
export function Root() {
  const [simulation, setSimulation] = useState(false)
  const route = usePublicRoute()
  if (route)
    return (
      <Suspense
        fallback={
          <p className="authshell" role="status">
            Ouverture…
          </p>
        }
      >
        {route.kind === 'privacy' ? (
          <PrivacyPage />
        ) : route.kind === 'order' ? (
          <PublicOrderPage key={route.token} token={route.token} channel={route.channel} />
        ) : (
          <PublicTrackingPage key={route.trackingToken} trackingToken={route.trackingToken} />
        )}
      </Suspense>
    )
  if (simulation)
    return (
      <Suspense
        fallback={
          <p className="authshell" role="status">
            Ouverture de la boutique d’exemple…
          </p>
        }
      >
        <DemoMode onExit={() => setSimulation(false)} />
      </Suspense>
    )
  return (
    <AuthGate onSimulation={() => setSimulation(true)}>
      {(shop, signOut, updateShop, userId) => (
        // Shared device in counter mode: the owner's pages stay closed until the owner's code.
        <CounterGate shop={shop} userId={userId} signOut={signOut}>
          <App
            shop={shop}
            userId={userId}
            signOut={signOut}
            updateShop={updateShop}
            onSimulation={() => setSimulation(true)}
          />
        </CounterGate>
      )}
    </AuthGate>
  )
}
