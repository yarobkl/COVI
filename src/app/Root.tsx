import { useState } from 'react'
import '../styles/index.css'
import { AuthGate } from '../features/auth/AuthGate'
import { DemoMode } from '../features/demo/DemoMode'
import { App } from './App'
import { LegacyPage } from './LegacyPage'

// index.html has no <html lang>: screen readers must read French.
document.documentElement.lang = 'fr'

/** Switches between the simulation (no account needed) and the signed-in application. */
export function Root() {
  const [simulation, setSimulation] = useState(false)
  if (simulation)
    return (
      <LegacyPage>
        <DemoMode onExit={() => setSimulation(false)} />
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
