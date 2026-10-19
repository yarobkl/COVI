// Passerelle API Stock COVI : testable en Node, executable par une Edge Function Supabase.
// Auth utilisateur JWT, acces sous RLS, correction atomique via RPC, jamais de service_role.
const uuid = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i
const reasons = new Set(['restock', 'loss', 'theft', 'count_error'])
const statuses = new Set(['all', 'active', 'sold', 'archived'])

const readJson = async (response) => response.json().catch(() => null)
const validQuantity = (value) => Number.isInteger(value) && value >= 0 && value <= 100000

export function createStockApiHandler(env, transport = fetch) {
  const rawBase = String(env.SUPABASE_URL || '')
  const base = rawBase.endsWith('/') ? rawBase.slice(0, -1) : rawBase
  const key = env.SUPABASE_ANON_KEY || ''
  const origins = new Set(
    (env.COVI_STOCK_API_ORIGINS || 'https://covi-snowy.vercel.app')
      .split(',').map((x) => x.trim()).filter(Boolean)
  )

  return async function stockApi(request) {
    const origin = request.headers.get('origin')
    const cors = { 'Vary': 'Origin', 'Cache-Control': 'no-store' }
    if (origin && !origins.has(origin)) {
      return new Response(JSON.stringify({ error: 'origin_not_allowed' }), {
        status: 403, headers: { ...cors, 'Content-Type': 'application/json' }
      })
    }
    if (origin) cors['Access-Control-Allow-Origin'] = origin
    cors['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    cors['Access-Control-Allow-Headers'] = 'authorization, apikey, content-type'
    const respond = (body, status = 200) => new Response(JSON.stringify(body), {
      status, headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' }
    })
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
    if (request.method !== 'GET' && request.method !== 'POST') {
      return respond({ error: 'method_not_allowed' }, 405)
    }
    if (!base.startsWith('https://') || !key) return respond({ error: 'unavailable' }, 503)

    const auth = request.headers.get('authorization') || ''
    if (!auth.startsWith('Bearer ') || auth.length <= 7 || auth.slice(7).includes(' ')) return respond({ error: 'authentication_required' }, 401)
    const headers = { apikey: key, authorization: auth, accept: 'application/json' }
    try {
      // Verification du JWT par GoTrue. Le jeton utilisateur reste utilise pour toutes
      // les requetes PostgREST afin de conserver la RLS de COVI.
      const identity = await transport(base + '/auth/v1/user', { headers })
      const person = await readJson(identity)
      if (!identity.ok || !person?.id || !uuid.test(person.id)) {
        return respond({ error: 'authentication_required' }, 401)
      }

      const url = new URL(request.url)
      const isAdjust = url.pathname.endsWith('/stock-api/adjust')
      const isRoot = url.pathname.endsWith('/stock-api') || url.pathname === '/'
      if (request.method === 'GET' && isRoot) {
        const shopId = url.searchParams.get('shop_id') || ''
        const status = url.searchParams.get('status') || 'all'
        const limitRaw = url.searchParams.get('limit') || '50'
        const offsetRaw = url.searchParams.get('offset') || '0'
        if (!uuid.test(shopId) || !statuses.has(status) ||
            !Array.from(limitRaw).every((c) => c >= '0' && c <= '9') ||
            !Array.from(offsetRaw).every((c) => c >= '0' && c <= '9')) {
          return respond({ error: 'invalid_parameters' }, 400)
        }
        const limit = Number(limitRaw), offset = Number(offsetRaw)
        if (!Number.isInteger(limit) || limit < 1 || limit > 100 ||
            !Number.isSafeInteger(offset) || offset > 10000) {
          return respond({ error: 'invalid_pagination' }, 400)
        }
        const own = new URL(base + '/rest/v1/shops')
        own.searchParams.set('select', 'id')
        own.searchParams.set('id', 'eq.' + shopId)
        own.searchParams.set('owner_id', 'eq.' + person.id)
        own.searchParams.set('limit', '1')
        const owning = await transport(own, { headers })
        if (!owning.ok) return respond({ error: 'unavailable' }, 503)
        const shops = await readJson(owning)
        if (!Array.isArray(shops) || shops.length === 0) {
          return respond({ error: 'shop_not_found' }, 404)
        }
        const query = new URL(base + '/rest/v1/products')
        query.searchParams.set('select',
          'id,shop_id,name,category,brand,size,quantity_on_hand,is_unique_piece,status,updated_at,is_test')
        query.searchParams.set('shop_id', 'eq.' + shopId)
        if (status !== 'all') query.searchParams.set('status', 'eq.' + status)
        query.searchParams.set('order', 'created_at.desc,id.desc')
        query.searchParams.set('limit', String(limit))
        query.searchParams.set('offset', String(offset))
        const result = await transport(query, { headers })
        if (!result.ok) return respond({ error: 'unavailable' }, 503)
        const products = await readJson(result)
        if (!Array.isArray(products)) return respond({ error: 'unavailable' }, 503)
        return respond({ shop_id: shopId, products, next_offset: products.length === limit ? offset + limit : null })
      }

      if (request.method !== 'POST' || !isAdjust) return respond({ error: 'not_found' }, 404)
      if (!(request.headers.get('content-type') || '').toLowerCase().startsWith('application/json')) {
        return respond({ error: 'json_required' }, 415)
      }
      const raw = await request.text()
      if (raw.length > 4096) return respond({ error: 'body_too_large' }, 413)
      let body
      try { body = JSON.parse(raw) } catch { return respond({ error: 'invalid_json' }, 400) }
      if (!body || Array.isArray(body) || typeof body !== 'object' ||
          !uuid.test(body.product_id || '') ||
          !validQuantity(body.quantity) || !validQuantity(body.expected_quantity) ||
          !reasons.has(body.reason) ||
          (body.note != null && (typeof body.note !== 'string' || body.note.length > 200 ||
            Array.from(body.note).some((c) => c.charCodeAt(0) < 32 || c.charCodeAt(0) === 127)))) {
        return respond({ error: 'invalid_stock_adjustment' }, 400)
      }
      const result = await transport(base + '/rest/v1/rpc/adjust_product_stock_if_unchanged', {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          p_product_id: body.product_id,
          p_expected_quantity: body.expected_quantity,
          p_quantity: body.quantity,
          p_reason: body.reason,
          p_note: body.note?.trim() || null
        })
      })
      if (!result.ok) {
        const problem = await readJson(result)
        const message = problem?.message || ''
        if (message.includes('STOCK_CONFLICT')) return respond({ error: 'stock_conflict', message: 'Relisez le stock avant de corriger.' }, 409)
        if (message.includes('Shop not found') || message.includes('Product not found')) return respond({ error: 'forbidden' }, 403)
        const invalid = ['Invalid', 'Restock must increase', 'Loss must decrease', 'Unique piece', 'Stock unchanged']
        if (invalid.some((prefix) => message.startsWith(prefix))) return respond({ error: 'invalid_stock_adjustment' }, 400)
        return respond({ error: 'unavailable' }, 503)
      }
      const updated = await readJson(result)
      if (!updated || typeof updated !== 'object' || !uuid.test(updated.id || '')) {
        return respond({ error: 'unavailable' }, 503)
      }
      return respond({ product: updated })
    } catch {
      return respond({ error: 'unavailable' }, 503)
    }
  }
}
