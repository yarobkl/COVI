import { lazy, Suspense, useEffect, useState } from 'react'
import '../styles/index.css'
import { AuthGate } from '../features/auth/AuthGate'
import { categoryCheckoutEnabled } from '../lib/checkoutFeatureFlag'
import { parseGuestOrderHash } from '../features/checkout/publicRoute'
import { PublicOrderRequestPage } from '../features/checkout/PublicOrderRequestPage'
import { App } from './App'
import { LegacyPage } from './LegacyPage'

// The example shop is only opened on demand: kept out of the first download.
const DemoMode = lazy(() =>
  import('../features/demo/DemoMode').then((m) => ({ default: m.DemoMode })),
)

// index.html has no <html lang>: screen readers must read French.
document.documentElement.lang = 'fr'

/** Switches between the simulation (no account needed) and the signed-in application. */
export function Root() {
  const [simulation, setSimulation] = useState(false)
  const [guestHash, setGuestHash] = useState(() => window.location.hash)
  useEffect(() => {
    const onHashChange = () => setGuestHash(window.location.hash)
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  }, [])

  // Public QR/social requests are the ONLY guest screen. Disabled at build
  // time in production until the PostgreSQL RPCs and abuse controls are live.
  const guest = categoryCheckoutEnabled ? parseGuestOrderHash(guestHash) : null
  if (guest) {
    return <PublicOrderRequestPage
      key={guest.token + ':' + guest.channel}
      token={guest.token} channel={guest.channel}
    />
  }

  if (simulation)
    return (
      <LegacyPage>
        <Suspense
          fallback={
            <p className="authshell" role="status">
              Ouverture de la boutique d’exemple…
            </p>
          }
        >
          <DemoMode onExit={() => setSimulation(false)} />
        </Suspense>
      </LegacyPage>
    )
  return (
    <AuthGate onSimulation={() => setSimulation(true)}>
      {(shop, signOut, updateShop) => (
        <App
          shop={shop}
          signOut={signOut}
          updateShop={updateShop}
          onSimulation={() => setSimulation(true)}
        />
      )}
    </AuthGate>
  )
}
