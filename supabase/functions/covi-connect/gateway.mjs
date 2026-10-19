// COVI Connect: multi-tenant server-to-server website bridge.
// No browser access to partner credentials; no external "paid" event can create a sale.
const UUID = /^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$/i
const KEY = /^covi_site_[a-f0-9]{64}$/
const TEXT = /^[^\u0000-\u001f\u007f]*$/
const METHODS = new Set(['cash', 'mobile_money', 'card', 'bank_transfer'])
const json = (status, body, headers = {}) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...headers }
})
const read = async (response) => response.json().catch(() => null)
const validText = (value, max, min = 1) =>
  typeof value === 'string' && value.trim().length >= min &&
  value.trim().length <= max && TEXT.test(value)
const isHttps = (value) => {
  try { const u = new URL(value); return u.protocol === 'https:' &&
    !u.username && !u.password && u.hostname.includes('.') && !u.hash } catch { return false }
}

export function createWebsiteConnectGateway(env, transport = fetch) {
  const base = String(env.SUPABASE_URL || '').replace(/\/$/, '')
  const service = String(env.SUPABASE_SERVICE_ROLE_KEY || '')
  const publishable = String(env.SUPABASE_ANON_KEY || '')
  const originAllowed = String(env.COVI_SITE_MANAGEMENT_ORIGIN || 'https://covi-snowy.vercel.app')
  const ready = base.startsWith('https://') && service.length > 30 && publishable.length > 20

  const rpc = async (fn, args, key, auth) => {
    const response = await transport(base + '/rest/v1/rpc/' + fn, {
      method: 'POST',
      headers: { apikey: key, authorization: 'Bearer ' + auth,
        'content-type': 'application/json' },
      body: JSON.stringify(args)
    })
    return { response, data: await read(response) }
  }

  return async function gateway(request) {
    const origin = request.headers.get('origin')
    const cors = origin === originAllowed
      ? { 'Access-Control-Allow-Origin': origin, 'Vary': 'Origin',
          'Access-Control-Allow-Headers': 'authorization,apikey,content-type',
          'Access-Control-Allow-Methods': 'GET,POST,OPTIONS' }
      : { 'Vary': 'Origin' }
    if (origin && origin !== originAllowed) return json(403, { error: 'origin_not_allowed' })
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
    if (!['GET','POST'].includes(request.method)) return json(405, { error: 'method_not_allowed' }, cors)
    if (!ready) return json(503, { error: 'unavailable' }, cors)
    const url = new URL(request.url)
    const path = url.pathname.replace(/\/$/, '')
    const managing = path.endsWith('/covi-connect/manage')
    const products = path.endsWith('/covi-connect/products')
    const orders = path.endsWith('/covi-connect/orders')
    if (!managing && !products && !orders) return json(404, { error: 'not_found' }, cors)
    try {
      if (managing) {
        const auth = request.headers.get('authorization') || ''
        if (!auth.startsWith('Bearer ') || auth.length <= 7) {
          return json(401, { error: 'authentication_required' }, cors)
        }
        const identity = await transport(base + '/auth/v1/user', {
          headers: { apikey: publishable, authorization: auth } })
        const user = await read(identity)
        if (!identity.ok || !UUID.test(user?.id || '')) {
          return json(401, { error: 'authentication_required' }, cors)
        }
        let fn, args
        if (request.method === 'GET') {
          const shopId = url.searchParams.get('shop_id')
          if (!UUID.test(shopId || '')) return json(400, { error: 'invalid_shop' }, cors)
          fn = 'list_website_connections'
          args = { p_shop_id: shopId }
        } else {
          if (!request.headers.get('content-type')?.startsWith('application/json'))
            return json(415, { error: 'json_required' }, cors)
          const bodyText = await request.text()
          if (bodyText.length > 2048) return json(413, { error: 'too_large' }, cors)
          let body
          try { body = JSON.parse(bodyText) } catch { return json(400, { error: 'invalid_json' }, cors) }
          if (body?.action === 'create' && UUID.test(body.shopId || '') &&
              validText(body.label, 80) && isHttps(body.siteUrl) && body.siteUrl.length <= 255) {
            fn = 'create_website_connection'
            args = { p_shop_id: body.shopId, p_label: body.label.trim(), p_site_url: body.siteUrl }
          } else if (body?.action === 'revoke' && UUID.test(body.connectionId || '')) {
            fn = 'revoke_website_connection'
            args = { p_connection_id: body.connectionId }
          } else return json(400, { error: 'invalid_management_request' }, cors)
        }
        const result = await rpc(fn, args, publishable, auth.slice(7))
        if (!result.response.ok) return json(
          result.response.status === 403 || result.data?.code === '42501' ? 403 : 400,
          { error: 'management_rejected' }, cors)
        return json(200, { result: result.data }, cors)
      }

      // Partner keys MUST remain on the merchant's server. Never from web browsers.
      if (origin) return json(403, { error: 'server_only' }, cors)
      const secret = request.headers.get('x-covi-key') || ''
      if (!KEY.test(secret)) return json(401, { error: 'invalid_credentials' })
      const verified = await rpc('authorize_website_connection', { p_secret: secret }, service, service)
      if (!verified.response.ok || !UUID.test(verified.data?.id || '') ||
          !UUID.test(verified.data?.shopId || '')) return json(401, { error: 'invalid_credentials' })
      const connectionId = verified.data.id
      const shopId = verified.data.shopId
      const action = products ? 'products' : request.method === 'POST' ? 'orders' : 'status'
      const quota = await rpc('consume_website_api_quota',
        { p_connection_id: connectionId, p_action: action }, service, service)
      if (!quota.response.ok) return json(503, { error: 'unavailable' })
      if (quota.data !== true) return json(429, { error: 'rate_limited' })

      if (products && request.method === 'GET') {
        const limitText = url.searchParams.get('limit') || '100'
        const offsetText = url.searchParams.get('offset') || '0'
        const limit = Number(limitText), offset = Number(offsetText)
        if (!/^\d+$/.test(limitText) || !/^\d+$/.test(offsetText) ||
            limit < 1 || limit > 100 || !Number.isSafeInteger(offset) || offset > 100000)
          return json(400, { error: 'invalid_pagination' })
        const q = new URL(base + '/rest/v1/products')
        q.searchParams.set('select',
          'id,name,category,brand,size,initial_sale_price,quantity_on_hand,status,updated_at')
        q.searchParams.set('shop_id', 'eq.' + shopId)
        q.searchParams.set('is_test', 'eq.false')
        q.searchParams.set('order', 'created_at.asc,id.asc')
        q.searchParams.set('limit', String(limit))
        q.searchParams.set('offset', String(offset))
        const result = await transport(q, { headers: { apikey: service, authorization: 'Bearer ' + service } })
        if (!result.ok) return json(503, { error: 'unavailable' })
        const rows = await read(result)
        if (!Array.isArray(rows)) return json(503, { error: 'unavailable' })
        return json(200, { products: rows.map(p => ({
          id: p.id, name: p.name, category: p.category, brand: p.brand, size: p.size,
          priceXaf: p.initial_sale_price, quantity: p.status === 'active' ? p.quantity_on_hand : 0,
          status: p.status, updatedAt: p.updated_at
        })), nextOffset: rows.length === limit ? offset + limit : null })
      }
      if (orders && request.method === 'GET') {
        const externalId = url.searchParams.get('external_id')
        if (!validText(externalId, 100)) return json(400, { error: 'invalid_external_id' })
        const result = await rpc('get_website_order_state',
          { p_connection_id: connectionId, p_external_order_id: externalId.trim() }, service, service)
        if (!result.response.ok) return json(503, { error: 'unavailable' })
        if (!result.data) return json(404, { error: 'order_not_found' })
        return json(200, { order: result.data })
      }
      if (orders && request.method === 'POST') {
        if (!request.headers.get('content-type')?.startsWith('application/json'))
          return json(415, { error: 'json_required' })
        const raw = await request.text()
        if (raw.length > 12000) return json(413, { error: 'too_large' })
        let body
        try { body = JSON.parse(raw) } catch { return json(400, { error: 'invalid_json' }) }
        if (!body || typeof body !== 'object' || Array.isArray(body) ||
            !validText(body.externalOrderId, 100) ||
            !validText(body.customerName, 60) ||
            !validText(body.customerPhone, 32, 6) ||
            !METHODS.has(body.paymentMethod) ||
            !['pickup','delivery'].includes(body.fulfillment) ||
            (body.fulfillment === 'delivery' && !validText(body.deliveryAddress, 240)) ||
            !Array.isArray(body.lines) || body.lines.length < 1 || body.lines.length > 20 ||
            body.lines.some(l => !l || typeof l !== 'object' ||
              !UUID.test(l.productId || '') || !Number.isInteger(l.quantity) ||
              l.quantity < 1 || l.quantity > 20 ||
              Object.keys(l).some(k => !['productId','quantity'].includes(k)))) {
          return json(400, { error: 'invalid_order' })
        }
        const result = await rpc('import_website_order', {
          p_connection_id: connectionId, p_external_order_id: body.externalOrderId.trim(),
          p_customer_name: body.customerName.trim(), p_customer_phone: body.customerPhone.trim(),
          p_payment_method: body.paymentMethod, p_fulfillment: body.fulfillment,
          p_delivery_address: body.deliveryAddress || null,
          p_lines: body.lines.map(l => ({ productId: l.productId, quantity: l.quantity }))
        }, service, service)
        if (!result.response.ok) {
          const e = String(result.data?.message || '')
          if (/Invalid|unavailable|Insufficient|Website access denied/.test(e)) return json(
            /Website access denied/.test(e) ? 403 : 422, { error: 'order_rejected' })
          return json(503, { error: 'unavailable' })
        }
        return json(200, { order: result.data, paymentConfirmed: false,
          message: 'Commande reçue : validation du paiement dans COVI requise.' })
      }
      return json(405, { error: 'method_not_allowed' })
    } catch {
      return json(503, { error: 'unavailable' }, cors)
    }
  }
}
