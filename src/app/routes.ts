// Pages of the signed-in application and their address in the URL hash (#/vendre…), so that the
// Android back button and the browser history move between pages.

export type PageId =
  'accueil' | 'vendre' | 'stock' | 'arrivages' | 'ventes' | 'charges' | 'bilan' | 'boutique'

/** Arrivages can be filtered to supplier orders or bales (« Commandes », « Ballons »). */
export type ArrivalFilter = 'commandes' | 'ballons'

export type Route = { page: PageId; filter?: ArrivalFilter }

export const pageIds: readonly PageId[] = [
  'accueil',
  'vendre',
  'stock',
  'arrivages',
  'ventes',
  'charges',
  'bilan',
  'boutique',
]

const isPage = (s: string): s is PageId => (pageIds as readonly string[]).includes(s)

/** Route of a URL hash; anything unknown (or empty) opens Accueil. */
export function parseHash(hash: string): Route {
  const [page = '', filter] = hash.replace(/^#\/?/, '').split('/').filter(Boolean)
  if (!isPage(page)) return { page: 'accueil' }
  if (page === 'arrivages' && (filter === 'commandes' || filter === 'ballons'))
    return { page, filter }
  return { page }
}

/** URL hash of a route: `#/` for Accueil, `#/arrivages/ballons`… */
export function routeHash(route: Route): string {
  if (route.page === 'accueil') return '#/'
  return route.filter && route.page === 'arrivages'
    ? `#/${route.page}/${route.filter}`
    : `#/${route.page}`
}

/** Identity of the page shown: each one gets its own React state (key). */
export const routeKey = (route: Route) => routeHash(route).slice(2) || 'accueil'
