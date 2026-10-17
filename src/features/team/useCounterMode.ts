import { useSyncExternalStore } from 'react'
import { isCounterMode, subscribeCounterMode } from '../../lib/counterMode'

/** Whether the owner's device is in counter mode for this shop (re-renders when it changes). */
export function useCounterMode(shopId: string) {
  return useSyncExternalStore(
    subscribeCounterMode,
    () => isCounterMode(shopId),
    () => false,
  )
}
