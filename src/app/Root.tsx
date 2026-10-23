import { lazy, Suspense, useEffect, useState } from 'react'
import '../styles/index.css'
import { AuthGate } from '../features/auth/AuthGate'
import { CounterGate } from '../features/team/CounterGate'
import { parsePublicHash } from '../lib/publicOrders'
import { parseRestaurantQrHash } from '../lib/restaurantQr'
import { App } from './App'

// The example shop is only opened on demand: kept out of the first download.
const AdminPage = lazy(() =>
  import('../features/admin/AdminPage').then((m) => ({ default: m.AdminPage })),
)

const DemoMode = lazy(() =>
  import('../features/demo/DemoMode').then((m) => ({ default: m.DemoMode })),
)

// Customer pages opened by a shop's QR code or WhatsApp / TikTok link: no account, no app shell.
const PublicOrderPage = lazy(() =>
  import('../features/orders/PublicOrderPage').then((m) => ({ default: m.PublicOrderPage })),
)
const PublicRestaurantTablePage = lazy(() =>
  import('../features/restaurant/PublicRestaurantTablePage').then((m) => ({
    default: m.PublicRestaurantTablePage,
  })),
)
const PrivacyPage = lazy(() =>
  import('../features/legal/PrivacyPage').then((m) => ({ default: m.PrivacyPage })),
)
const TermsPage = lazy(() =>
  import('../features/legal/TermsPage').then((m) => ({ default: m.TermsPage })),
)
const SupportPage = lazy(() =>
  import('../features/legal/SupportPage').then((m) => ({ default: m.SupportPage })),
)
const PublicTrackingPage = lazy(() =>
  import('../features/orders/PublicTrackingPage').then((m) => ({ default: m.PublicTrackingPage })),
)

/** Pages publiques, lisibles sans compte : commande, suivi, confidentialité, conditions, aide. */
type LegalRoute = { kind: 'privacy' } | { kind: 'terms' } | { kind: 'support' }
const legalPages: Record<string, LegalRoute> = {
  confidentialite: { kind: 'privacy' },
  conditions: { kind: 'terms' },
  aide: { kind: 'support' },
}
const publicRoute = (hash: string) => {
  const legalPage = /^#\/(confidentialite|conditions|aide)\/?$/.exec(hash)
  return legalPage
    ? legalPages[legalPage[1]]
    : (parseRestaurantQrHash(hash) ?? parsePublicHash(hash))
}

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

/** Routes admin outside the merchant application, without conditional React hooks. */
export function Root() {
  if (window.location.pathname === '/admin' || window.location.pathname === '/admin/') {
    return (
      <Suspense
        fallback={
          <p className="authshell" role="status">
            Ouverture de l’administration…
          </p>
        }
      >
        <AdminPage />
      </Suspense>
    )
  }
  return <MerchantRoot />
}

/** Switches between the simulation (no account needed) and the signed-in application. */
function MerchantRoot() {
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
        ) : route.kind === 'terms' ? (
          <TermsPage />
        ) : route.kind === 'support' ? (
          <SupportPage />
        ) : route.kind === 'order' ? (
          <PublicOrderPage key={route.token} token={route.token} channel={route.channel} />
        ) : route.kind === 'restaurantTable' ? (
          <PublicRestaurantTablePage key={route.token} token={route.token} />
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
