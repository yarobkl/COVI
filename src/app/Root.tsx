import { lazy, Suspense, useState } from 'react'
import '../styles/index.css'
import { AuthGate } from '../features/auth/AuthGate'
import { App } from './App'

// The example shop is only opened on demand: kept out of the first download.
const DemoMode = lazy(() =>
  import('../features/demo/DemoMode').then((m) => ({ default: m.DemoMode })),
)

// index.html has no <html lang>: screen readers must read French.
document.documentElement.lang = 'fr'

/** Switches between the simulation (no account needed) and the signed-in application. */
export function Root() {
  // Where the example shop was opened from: the sign-in page, or the signed-in shop.
  const [simulation, setSimulation] = useState<false | 'visitor' | 'shop'>(false)
  if (simulation)
    return (
      <Suspense
        fallback={
          <p className="skeleton__caption" role="status" style={{ padding: 'var(--space-6)' }}>
            Ouverture de la boutique d’exemple…
          </p>
        }
      >
        <DemoMode onExit={() => setSimulation(false)} signedIn={simulation === 'shop'} />
      </Suspense>
    )
  return (
    <AuthGate onSimulation={() => setSimulation('visitor')}>
      {(shop, signOut, updateShop) => (
        <App
          shop={shop}
          signOut={signOut}
          updateShop={updateShop}
          onSimulation={() => setSimulation('shop')}
        />
      )}
    </AuthGate>
  )
}
