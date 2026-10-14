import { useSyncExternalStore } from 'react'
import type { TillSession } from '../../lib/team'
import { getTillSession, subscribeTillSession } from '../../lib/tillSession'

/** Current till session of the shop (re-renders when it opens, closes or expires). */
export function useTillSession(shopId: string): TillSession | null {
  return useSyncExternalStore(
    subscribeTillSession,
    () => getTillSession(shopId, Date.now(), false),
    () => null,
  )
}
