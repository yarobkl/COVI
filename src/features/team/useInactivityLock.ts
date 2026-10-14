import { useEffect, useRef } from 'react'

/** The till locks itself after this much time without a touch or a key (5 minutes). */
export const INACTIVITY_MS = 5 * 60 * 1000

/**
 * Calls `onLock` after 5 minutes without a touch, a click or a key, while `active`. Any activity
 * restarts the 5 minutes.
 */
export function useInactivityLock(active: boolean, onLock: () => void) {
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined)
  const lock = useRef(onLock)
  useEffect(() => {
    lock.current = onLock
  })
  useEffect(() => {
    if (!active) return
    const restart = () => {
      if (timer.current) clearTimeout(timer.current)
      timer.current = setTimeout(() => lock.current(), INACTIVITY_MS)
    }
    restart()
    const events = ['pointerdown', 'keydown', 'touchstart'] as const
    events.forEach((e) => window.addEventListener(e, restart, { passive: true }))
    return () => {
      if (timer.current) clearTimeout(timer.current)
      events.forEach((e) => window.removeEventListener(e, restart))
    }
  }, [active])
}
