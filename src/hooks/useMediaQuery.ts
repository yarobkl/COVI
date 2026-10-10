import { useSyncExternalStore } from 'react'

/** Whether a CSS media query matches now (false where matchMedia is missing, e.g. tests). */
export function useMediaQuery(query: string) {
  return useSyncExternalStore(
    (onChange) => {
      if (typeof window.matchMedia !== 'function') return () => {}
      const list = window.matchMedia(query)
      list.addEventListener('change', onChange)
      return () => list.removeEventListener('change', onChange)
    },
    () => typeof window.matchMedia === 'function' && window.matchMedia(query).matches,
  )
}

/** The computer layout: sommaire on the left, sale form beside the articles. */
export const DESKTOP = '(min-width: 1024px)'
