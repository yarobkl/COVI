// Lecture seule des menus de table via QR COVI Restaurant.
// Séparé du canal boutique. Aucun droit d'écriture client à ce stade.
// Testable sous Node et Deno; jamais de clé serveur transmise au navigateur.
const QR = /^[0-9a-f]{64}$/
const headers = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store',
  'x-content-type-options': 'nosniff', 'vary': 'Origin' }

function answer(status, value, origin) {
  return new Response(JSON.stringify(value), {
    status, headers: { ...headers, ...(origin ? { 'access-control-allow-origin': origin } : {}) },
  })
}

export function createRestaurantQrGateway(env, fetchImpl = fetch) {
  const origins = String(env.COVI_PUBLIC_ORIGIN ?? '')
    .split(',').map(s => s.trim()).filter(s => {
      try {
        const url = new URL(s)
        return url.origin === s && (url.protocol === 'https:' || url.hostname === 'localhost')
      } catch { return false }
    })
  const key = env.SUPABASE_SERVICE_ROLE_KEY ?? ''
  let apiValid = false
  try {
    const api = new URL(env.SUPABASE_URL)
    apiValid = api.protocol === 'https:' && api.pathname === '/'
  } catch { /* fail closed */ }
  const enabled = env.COVI_RESTAURANT_QR_ENABLED === 'true' &&
    apiValid && origins.length > 0 && key.length > 30

  return async (request) => {
    const requestedOrigin = request.headers.get('origin')
    const origin = requestedOrigin && origins.includes(requestedOrigin) ? requestedOrigin : null
    if (!origin) return answer(403, { error: 'Origine non autorisée.' }, null)
    if (request.method === 'OPTIONS') return new Response(null, {
      status: 204,
      headers: {
        'access-control-allow-origin': origin,
        'access-control-allow-methods': 'GET, OPTIONS',
        'access-control-allow-headers': 'content-type, apikey, authorization, x-client-info',
        'access-control-max-age': '600', vary: 'Origin',
      },
    })
    if (request.method !== 'GET') return answer(405, { error: 'Opération non autorisée.' }, origin)
    if (!enabled) return answer(503, { error: 'La carte QR du restaurant n’est pas encore disponible.' }, origin)

    const uri = new URL(request.url)
    const token = uri.searchParams.get('table') ?? ''
    if (!QR.test(token)) return answer(400, { error: 'QR code de table invalide.' }, origin)
    try {
      const response = await fetchImpl(new URL('/rest/v1/rpc/restaurant_qr_catalog', env.SUPABASE_URL), {
        method: 'POST',
        headers: {
          apikey: key, 'content-type': 'application/json',
          ...(key.startsWith('eyJ') ? { authorization: `Bearer ${key}` } : {}),
        },
        body: JSON.stringify({ p_qr_token: token }),
      })
      if (!response.ok) return answer(503, { error: 'Carte momentanément indisponible.' }, origin)
      const record = await response.json()
      if (!record) return answer(404, { error: 'Table introuvable ou désactivée.' }, origin)
      if (typeof record.restaurantName !== 'string' || typeof record.tableName !== 'string' ||
        !Number.isInteger(record.capacity) || record.capacity < 1 ||
        !['free', 'collecting', 'occupied'].includes(record.tableState) ||
        !Array.isArray(record.menu)) {
        return answer(503, { error: 'Carte momentanément indisponible.' }, origin)
      }
      // Projection already strips customer records; never proxy arbitrary REST results.
      const menu = []
      for (const item of record.menu) {
        if (menu.length >= 300) return answer(503, { error: 'Carte trop volumineuse, contactez le personnel.' }, origin)
        if (typeof item?.name !== 'string' || typeof item?.category !== 'string' ||
          typeof item?.id !== 'string' || !['dish', 'drink', 'dessert'].includes(item.kind) ||
          !Number.isSafeInteger(item.priceXaf) || item.priceXaf < 0 ||
          typeof item.available !== 'boolean') {
          return answer(503, { error: 'Carte momentanément indisponible.' }, origin)
        }
        menu.push({ id: item.id, name: item.name, category: item.category, kind: item.kind,
          priceXaf: item.priceXaf, available: item.available })
      }
      return answer(200, {
        restaurantName: record.restaurantName,
        tableName: record.tableName,
        capacity: record.capacity,
        tableState: record.tableState,
        menu,
        orderingOpen: false, // DO NOT promise that a public booking/order will be recorded.
      }, origin)
    } catch {
      return answer(503, { error: 'Connexion au restaurant momentanément indisponible.' }, origin)
    }
  }
}
