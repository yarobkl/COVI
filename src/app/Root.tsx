import { lazy, Suspense, useState } from 'react'
import '../styles/index.css'
import { AuthGate } from '../features/auth/AuthGate'
import { App } from './App'

// The admin page is only opened on /admin: kept out of the merchant download.
const AdminPage = lazy(() =>
  import('../features/admin/AdminPage').then((m) => ({ default: m.AdminPage })),
)

// The example shop is only opened on demand: kept out of the first download.
const DemoMode = lazy(() =>
  import('../features/demo/DemoMode').then((m) => ({ default: m.DemoMode })),
)

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
      {(shop, signOut, updateShop, account) => (
        // A new key per shop: changing shop unmounts every page and its state (products, stock,
        // sales, figures) and loads the other shop from scratch. Nothing is carried over.
        <App
          key={shop.id}
          shop={shop}
          account={account}
          signOut={signOut}
          updateShop={updateShop}
          onSimulation={() => setSimulation('shop')}
        />
      )}
    </AuthGate>
  )
}
