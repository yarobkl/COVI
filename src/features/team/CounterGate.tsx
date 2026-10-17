import type { ReactNode } from 'react'
import type { Shop } from '../../lib/types'
import { CounterApp } from './CounterApp'
import { useCounterMode } from './useCounterMode'
import { useTillSession } from './useTillSession'

/**
 * The management account belongs to the whole shop. During checkout the UI
 * switches into the named cashier's PIN-verified till, without signing out.
 *
 * This is a workflow guard, NOT a security boundary for the manager's shared JWT.
 */
export function CounterGate({
  shop,
  userId,
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
  if (counter || till) return <CounterApp shop={shop} userId={userId} signOut={signOut} />
  return <>{children}</>
}
