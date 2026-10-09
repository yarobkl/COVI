import { useState } from 'react'
import { AuthGate } from '../features/auth/AuthGate'
import { DemoMode } from '../features/demo/DemoMode'
import { App } from './App'

/** Switches between the simulation (no account needed) and the signed-in application. */
export function Root() {
  const [simulation, setSimulation] = useState(false)
  if (simulation) return <DemoMode onExit={() => setSimulation(false)} />
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
