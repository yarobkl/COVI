// Public guest gateway. This file is runnable in both Deno Edge and Node tests.
// No owner action, payment confirmation, or inventory mutation is exposed here.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const encoder = new TextEncoder()
const corsMethods = 'GET, POST, OPTIONS'
const corsHeaders = 'content-type'
const jsonHeaders = { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }

function json(status, data, origin) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      ...jsonHeaders,
      Vary: 'Origin',
      ...(origin ? { 'Access-Control-Allow-Origin': origin } : {}),
    },
  })
}

function validSettings(env) {
  try {
    const origin = new URL(env.COVI_PUBLIC_ORIGIN)
    const api = new URL(env.SUPABASE_URL)
    return (
      env.COVI_GATEWAY_ENABLED === 'true' &&
      origin.origin === env.COVI_PUBLIC_ORIGIN &&
      (origin.protocol === 'https:' || origin.hostname === 'localhost') &&
      api.protocol === 'https:' &&
      api.pathname === '/' &&
      typeof env.COVI_SUPABASE_SECRET_KEY === 'string' &&
      env.COVI_SUPABASE_SECRET_KEY.length > 30 &&
      typeof env.COVI_GATEWAY_PEPPER === 'string' &&
      env.COVI_GATEWAY_PEPPER.length >= 32 &&
      typeof env.COVI_TURNSTILE_SECRET === 'string' &&
      env.COVI_TURNSTILE_SECRET.length >= 16
    )
  } catch {
    return false
  }
}

function invalidControl(value) {
  return /[\u0000-\u001f\u007f]/.test(value)
}

function validRequest(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return false
  if (
    !UUID.test(body.token) ||
    !UUID.test(body.operationId) ||
    !['qr', 'social'].includes(body.channel) ||
    !['pickup', 'delivery'].includes(body.fulfillment) ||
    !Array.isArray(body.lines) ||
    body.lines.length < 1 ||
    body.lines.length > 20 ||
    typeof body.challenge !== 'string' ||
    body.challenge.length < 10 ||
    body.challenge.length > 4096 ||
    invalidControl(body.challenge)
  ) return false

  const phone = body.phone ?? ''
  const note = body.note ?? ''
  if (
    typeof phone !== 'string' ||
    typeof note !== 'string' ||
    phone.trim().length > 32 ||
    note.trim().length > 500 ||
    invalidControl(phone) ||
    invalidControl(note) ||
    (body.fulfillment === 'delivery' && !phone.trim())
  ) return false

  let total = 0
  const categories = new Map()
  for (const line of body.lines) {
    if (
      !line ||
      typeof line !== 'object' ||
      Array.isArray(line) ||
      !UUID.test(line.categoryId) ||
      !Number.isSafeInteger(line.quantity) ||
      line.quantity < 1 ||
      line.quantity > 20 ||
      !Number.isSafeInteger(line.unitPriceXaf) ||
      line.unitPriceXaf < 1 ||
      line.unitPriceXaf > 999999999
    ) return false
    const count = (categories.get(line.categoryId) ?? 0) + line.quantity
    if (count > 20) return false
    categories.set(line.categoryId, count)
    total += line.quantity * line.unitPriceXaf
    if (total > 2000000000) return false
  }
  return true
}

async function limitedJson(request) {
  const length = Number(request.headers.get('content-length'))
  if (Number.isFinite(length) && length > 12000) throw new Error('size')
  const reader = request.body?.getReader()
  if (!reader) throw new Error('body')
  const parts = []
  let size = 0
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    size += value.byteLength
    if (size > 12000) {
      await reader.cancel()
      throw new Error('size')
    }
    parts.push(value)
  }
  const bytes = new Uint8Array(size)
  let offset = 0
  for (const part of parts) {
    bytes.set(part, offset)
    offset += part.length
  }
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes))
}

async function hmac(secret, value) {
  const key = await crypto.subtle.importKey(
    'raw',
    encoder.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(value))
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('')
}

function sourceFingerprint(request) {
  // Best effort only: proxy forwarding headers may be spoofable.
  // Turnstile verification and token-wide atomic SQL limits are mandatory.
  const forwarded = request.headers.get('x-forwarded-for')
  const raw = forwarded?.split(',').at(-1)?.trim() || request.headers.get('cf-connecting-ip')
  if (!raw || raw.length > 64 || !/^[0-9a-fA-F:.]+$/.test(raw)) return 'unknown'
  return raw
}

async function backendRpc(env, fetchImpl, name, payload) {
  const url = new URL('/rest/v1/rpc/' + name, env.SUPABASE_URL)
  const response = await fetchImpl(url, {
    method: 'POST',
    headers: { apikey: env.COVI_SUPABASE_SECRET_KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  })
  if (!response.ok) throw new Error('backend')
  return response.json()
}

async function verifyTurnstile(env, fetchImpl, challenge) {
  const body = new URLSearchParams({
    secret: env.COVI_TURNSTILE_SECRET,
    response: challenge,
  })
  const response = await fetchImpl('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    body,
  })
  if (!response.ok) throw new Error('turnstile')
  const outcome = await response.json()
  return (
    outcome?.success === true &&
    outcome.hostname === new URL(env.COVI_PUBLIC_ORIGIN).hostname &&
    outcome.action === 'covi_checkout'
  )
}

export function createPublicCheckoutGateway(env, fetchImpl = fetch) {
  return async function handle(request) {
    const origin = request.headers.get('origin')
    const allowedOrigin = origin === env.COVI_PUBLIC_ORIGIN ? origin : null
    if (!allowedOrigin) return json(403, { error: 'Origine non autorisée.' }, null)
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': allowedOrigin,
          'Access-Control-Allow-Methods': corsMethods,
          'Access-Control-Allow-Headers': corsHeaders,
          'Access-Control-Max-Age': '600',
          Vary: 'Origin',
          'Cache-Control': 'no-store',
        },
      })
    }
    if (!['GET', 'POST'].includes(request.method))
      return json(405, { error: 'Méthode interdite.' }, allowedOrigin)
    if (!validSettings(env))
      return json(503, { error: 'Commandes indisponibles pour le moment.' }, allowedOrigin)

    try {
      const isCatalog = request.method === 'GET'
      const url = new URL(request.url)
      let token
      let body
      if (isCatalog) {
        token = url.searchParams.get('token')
      } else {
        if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json'))
          return json(415, { error: 'Format de demande non pris en charge.' }, allowedOrigin)
        try {
          body = await limitedJson(request)
        } catch {
          return json(400, { error: 'Demande invalide ou trop volumineuse.' }, allowedOrigin)
        }
        if (!validRequest(body))
          return json(400, { error: 'Vérifiez les données et le contrôle anti-robot.' }, allowedOrigin)
        token = body.token
      }
      if (!UUID.test(token))
        return json(400, { error: 'Lien de commande invalide.' }, allowedOrigin)

      // Fixed database ceilings, enforced atomically across edge instances.
      const source = sourceFingerprint(request)
      const sourceDigest = await hmac(env.COVI_GATEWAY_PEPPER, 'source:' + token + ':' + source)
      const linkDigest = await hmac(env.COVI_GATEWAY_PEPPER, 'link:' + token)
      const limits = isCatalog
        ? [['catalog_source_minute', sourceDigest], ['catalog_link_minute', linkDigest]]
        : [
            ['order_source_minute', sourceDigest],
            ['order_source_day', sourceDigest],
            ['order_link_minute', linkDigest],
          ]
      for (const [kind, digest] of limits) {
        const accepted = await backendRpc(env, fetchImpl, 'consume_checkout_gateway_quota', {
          p_digest: digest,
          p_kind: kind,
        })
        if (accepted !== true)
          return json(429, { error: 'Trop de demandes. Réessayez plus tard.' }, allowedOrigin)
      }

      if (isCatalog) {
        const catalog = await backendRpc(env, fetchImpl, 'get_checkout_public_catalog', {
          p_token: token,
        })
        if (
          !catalog ||
          typeof catalog.shopName !== 'string' ||
          !Array.isArray(catalog.categories)
        ) throw new Error('catalog')
        return json(200, catalog, allowedOrigin)
      }

      if (!(await verifyTurnstile(env, fetchImpl, body.challenge)))
        return json(403, { error: 'Vérification anti-robot non validée.' }, allowedOrigin)

      const result = await backendRpc(env, fetchImpl, 'submit_checkout_public_order', {
        p_token: token,
        p_channel: body.channel,
        p_operation_id: body.operationId,
        p_lines: body.lines,
        p_customer_phone: body.phone?.trim() || null,
        p_customer_note: body.note?.trim() || null,
        p_fulfillment: body.fulfillment,
      })
      if (!result || !UUID.test(result.orderId) || result.status !== 'submitted')
        throw new Error('order')
      return json(200, {
        orderId: result.orderId,
        status: result.status,
        amountXaf: result.amountXaf,
      }, allowedOrigin)
    } catch {
      // No database, token, key, IP, phone or provider error details in responses.
      return json(503, { error: 'Service temporairement indisponible.' }, allowedOrigin)
    }
  }
}
