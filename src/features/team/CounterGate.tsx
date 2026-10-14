import { useEffect, type ReactNode } from 'react'
import { enterCounterMode } from '../../lib/counterMode'
import type { Shop } from '../../lib/types'
import { CounterApp } from './CounterApp'
import { useCounterMode } from './useCounterMode'
import { useTillSession } from './useTillSession'

/**
 * Owner's space: the full application (`children`), or the counter space when a cashier holds
 * the till on this device. The owner pages are not rendered at all in counter mode.
 */
export function CounterGate({
  shop,
  userId,
  signOut,
  children,
}: {
  shop: Shop
  /** The signed-in owner (AuthGate): carts rung up at the counter are tied to this account. */
  userId: string
  signOut: () => Promise<void>
  children: ReactNode
}) {
  const counter = useCounterMode(shop.id)
  const till = useTillSession(shop.id)
  // A till session without the flag (kept by an older version): counter mode too.
  useEffect(() => {
    if (till && !counter) enterCounterMode(shop.id)
  }, [till, counter, shop.id])
  if (counter || till) return <CounterApp shop={shop} userId={userId} signOut={signOut} />
  return <>{children}</>
}
