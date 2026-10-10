import { useCallback, useEffect, useState } from 'react'
import { parseHash, routeHash, type Route } from './routes'

/**
 * Current page, read from the URL hash and kept in sync with it. Links (`href="#/vendre"`) and
 * `navigate` add a history entry, so the Android back button returns to the previous page.
 */
export function useHashRoute() {
  const [route, setRoute] = useState<Route>(() => parseHash(window.location.hash))
  useEffect(() => {
    const sync = () => setRoute(parseHash(window.location.hash))
    window.addEventListener('hashchange', sync)
    window.addEventListener('popstate', sync)
    return () => {
      window.removeEventListener('hashchange', sync)
      window.removeEventListener('popstate', sync)
    }
  }, [])
  const navigate = useCallback((next: Route) => {
    const hash = routeHash(next)
    if (hash !== (window.location.hash || '#/')) window.location.hash = hash
    else setRoute(parseHash(hash))
  }, [])
  return { route, navigate }
}
