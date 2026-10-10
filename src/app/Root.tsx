import { lazy, Suspense, useState } from 'react'
import '../styles/index.css'
import { AuthGate } from '../features/auth/AuthGate'
import { App } from './App'
import { LegacyPage } from './LegacyPage'

// The example shop is only opened on demand: kept out of the first download.
const AdminPage = lazy(() =>
  import('../features/admin/AdminPage').then((m) => ({ default: m.AdminPage })),
)

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
  const [simulation, setSimulation] = useState(false)
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
