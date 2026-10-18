// Public guest gateway. This file is runnable in both Deno Edge and Node tests.
// No owner action, payment confirmation, or inventory mutation is exposed here.
// Bound external dependency waits to prevent stalled privileged Edge requests.
const RPC_TIMEOUT_MS = 8000
const IMAGE_UPLOAD_TIMEOUT_MS = 12000
const TURNSTILE_TIMEOUT_MS = 8000
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

/** Parse JPEG headers without decoding the pixels.
 * Browser canvas re-encodes reference photos; reject untrusted metadata blocks
 * and decompression-bomb dimensions before uploading with service privileges.
 * This is intentionally stricter than a generic JPEG decoder.
 */
function safeReferenceJpeg(bytes) {
  const length = bytes.length
  if (length < 20 || length > 320000 ||
      bytes[0] !== 0xff || bytes[1] !== 0xd8 ||
      bytes[length - 2] !== 0xff || bytes[length - 1] !== 0xd9) return false

  let offset = 2
  let frameSeen = false
  let scanSeen = false
  while (offset < length - 2) {
    if (bytes[offset++] !== 0xff) return false
    while (offset < length - 2 && bytes[offset] === 0xff) offset++
    if (offset >= length - 2) return false
    const marker = bytes[offset++]
    // Embedded EXIF/XMP, Photoshop/IPTC and JPEG comments may leak location,
    // capture times or other metadata. We accept only canvas-style JPEG data.
    if ([0xe1, 0xed, 0xfe].includes(marker)) return false
    if (marker === 0x00 || marker === 0xd8 || marker === 0xd9 ||
        marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) return false
    if (offset + 2 > length - 2) return false

    const segmentLength = bytes[offset] * 256 + bytes[offset + 1]
    if (segmentLength < 2 || offset + segmentLength > length - 2) return false
    // Baseline, progressive and other JPEG SOF markers. They contain explicit
    // height/width independent of compressed byte size.
    const isFrame = (marker >= 0xc0 && marker <= 0xcf &&
      ![0xc4, 0xc8, 0xcc].includes(marker))
    if (isFrame) {
      if (frameSeen || segmentLength < 8) return false
      const height = bytes[offset + 3] * 256 + bytes[offset + 4]
      const width = bytes[offset + 5] * 256 + bytes[offset + 6]
      if (width < 1 || height < 1 || width > 4096 || height > 4096 ||
          width * height > 4000000) return false
      frameSeen = true
    }
    if (marker === 0xda) {
      if (!frameSeen || segmentLength < 6) return false
      scanSeen = true
      break
    }
    offset += segmentLength
  }
  return frameSeen && scanSeen
}

function decodeReferenceJpeg(value) {
  if (typeof value !== 'string' || value.length > 450000) return null
  const match = /^data:image\/jpeg;base64,([A-Za-z0-9+/]+={0,2})$/.exec(value)
  if (!match) return null
  try {
    const binary = atob(match[1])
    if (binary.length > 320000) return null
    const bytes = Uint8Array.from(binary, char => char.charCodeAt(0))
    return safeReferenceJpeg(bytes) ? bytes : null
  } catch {
    return null
  }
}

function validRequest(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return false
  if (
    !UUID.test(body.token) ||
    !UUID.test(body.operationId) ||
    !['qr', 'social'].includes(body.channel) ||
    !['pickup', 'delivery'].includes(body.fulfillment) ||
    !['cash', 'mobile_money', 'other'].includes(body.paymentMethod ?? 'cash') ||
    (body.referenceImage != null && !decodeReferenceJpeg(body.referenceImage)) ||
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
  const deliveryAddress = body.deliveryAddress ?? ''
  if (
    typeof phone !== 'string' ||
    typeof note !== 'string' ||
    typeof deliveryAddress !== 'string' ||
    phone.trim().length > 32 ||
    note.trim().length > 500 ||
    deliveryAddress.trim().length > 240 ||
    invalidControl(phone) ||
    invalidControl(note) ||
    invalidControl(deliveryAddress) ||
    (body.fulfillment === 'delivery' && (!phone.trim() || !deliveryAddress.trim()))
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
  if (Number.isFinite(length) && length > 475000) throw new Error('size')
  const reader = request.body?.getReader()
  if (!reader) throw new Error('body')
  const parts = []
  let size = 0
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    size += value.byteLength
    if (size > 475000) {
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
    signal: AbortSignal.timeout(RPC_TIMEOUT_MS),
    method: 'POST',
    headers: {
      apikey: env.COVI_SUPABASE_SECRET_KEY,
      // Legacy service_role JWT needs Authorization for some Kong/PostgREST gateways.
      // Opaque sb_secret keys are supplied only as apikey (never as JWT).
      ...(env.COVI_SUPABASE_SECRET_KEY.startsWith('eyJ')
        ? { Authorization: 'Bearer ' + env.COVI_SUPABASE_SECRET_KEY }
        : {}),
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  })
  if (!response.ok) throw new Error('backend')
  return response.json()
}

/** Only the Edge gateway can upload private, bounded JPEG references. */
async function saveCheckoutReference(env, fetchImpl, result, body) {
  const image = decodeReferenceJpeg(body.referenceImage)
  if (!image || !UUID.test(result.shopId) || !UUID.test(result.orderId))
    throw new Error('Invalid reference upload')
  const path = result.shopId + '/' + result.orderId + '/reference.jpg'
  const endpoint = new URL(
    '/storage/v1/object/covi-order-references/' + path,
    env.SUPABASE_URL,
  )
  const response = await fetchImpl(endpoint, {
    signal: AbortSignal.timeout(IMAGE_UPLOAD_TIMEOUT_MS),
    method: 'POST',
    headers: {
      apikey: env.COVI_SUPABASE_SECRET_KEY,
      ...(env.COVI_SUPABASE_SECRET_KEY.startsWith('eyJ')
        ? { Authorization: 'Bearer ' + env.COVI_SUPABASE_SECRET_KEY }
        : {}),
      'Content-Type': 'image/jpeg',
      'x-upsert': 'false',
      'Cache-Control': 'no-store',
    },
    body: image,
  })
  // A retry must never overwrite a previous screenshot.
  if (!response.ok && response.status !== 409) throw new Error('Storage upload failed')
  const attached = await backendRpc(
    env,
    fetchImpl,
    'attach_checkout_public_reference',
    {
      p_token: body.token,
      p_order_id: result.orderId,
      p_operation_id: body.operationId,
      p_image_path: path,
    },
  )
  if (attached !== true) throw new Error('Attachment authorization failed')
}

async function verifyTurnstile(env, fetchImpl, challenge) {
  const body = new URLSearchParams({
    secret: env.COVI_TURNSTILE_SECRET,
    response: challenge,
  })
  const response = await fetchImpl('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    signal: AbortSignal.timeout(TURNSTILE_TIMEOUT_MS),
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
      const url = new URL(request.url)
      const isTracking = request.method === 'GET' && url.searchParams.has('tracking')
      const isCatalog = request.method === 'GET' && !isTracking
      let token
      let body
      if (request.method === 'GET') {
        token = url.searchParams.get(isTracking ? 'tracking' : 'token')
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
      // A caller can invent unlimited random token UUIDs. Source quotas MUST
      // stay the same when a token changes, otherwise each guessed token
      // obtains a fresh quota bucket and grows the quota table without bound.
      const sourceDigest = await hmac(env.COVI_GATEWAY_PEPPER, 'source:' + source)
      const linkDigest = await hmac(env.COVI_GATEWAY_PEPPER, 'link:' + token)
      // Proxy IP headers can also be spoofed. A token-independent global
      // ceiling is a second backstop: it prevents forged source headers from
      // creating unbounded quota rows / backend calls.
      const globalKind = isTracking
        ? 'status_global_minute'
        : isCatalog
          ? 'catalog_global_minute'
          : 'order_global_minute'
      const globalDigest = await hmac(env.COVI_GATEWAY_PEPPER, 'global:' + globalKind)
      const limits = isTracking
        ? [
            [globalKind, globalDigest],
            ['status_source_minute', sourceDigest],
            ['status_token_minute', linkDigest],
          ]
        : isCatalog
          ? [
              [globalKind, globalDigest],
              ['catalog_source_minute', sourceDigest],
              ['catalog_link_minute', linkDigest],
            ]
          : [
              [globalKind, globalDigest],
              ['order_source_minute', sourceDigest],
              ['order_source_day', sourceDigest],
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

      if (isTracking) {
        // A dedicated random receipt capability: no customer data or payment
        // mutation can be requested using this GET endpoint.
        const tracked = await backendRpc(env, fetchImpl, 'get_checkout_guest_status', {
          p_tracking_token: token,
        })
        if (
          !tracked ||
          !UUID.test(tracked.orderId) ||
          typeof tracked.shopName !== 'string' ||
          !tracked.shopName.trim() ||
          !['submitted', 'approved', 'reserved', 'paid', 'cancelled', 'expired'].includes(
            tracked.status,
          ) ||
          !Number.isSafeInteger(tracked.amountXaf) ||
          tracked.amountXaf < 0 ||
          tracked.amountXaf > 2000000000
        ) throw new Error('invalid tracking status')
        if (tracked.status === 'paid') {
          const receipt = tracked.receipt
          if (
            !receipt ||
            typeof receipt.receiptNumber !== 'string' ||
            !receipt.receiptNumber ||
            typeof receipt.confirmedAt !== 'string' ||
            !Number.isFinite(Date.parse(receipt.confirmedAt)) ||
            typeof receipt.cashierFirstName !== 'string' ||
            !['cash', 'mobile_money', 'other'].includes(receipt.method) ||
            receipt.amountXaf !== tracked.amountXaf ||
            !Array.isArray(receipt.lines) ||
            receipt.lines.length < 1 ||
            receipt.lines.length > 40
          ) throw new Error('invalid paid receipt')
        }
        return json(200, {
          shopName: tracked.shopName,
          orderId: tracked.orderId,
          status: tracked.status,
          amountXaf: tracked.amountXaf,
          ...(tracked.status === 'paid' ? { receipt: tracked.receipt } : {}),
        }, allowedOrigin)
      }

      if (!(await verifyTurnstile(env, fetchImpl, body.challenge)))
        return json(403, { error: 'Vérification anti-robot non validée.' }, allowedOrigin)

      // A bot must not exhaust the whole shop's order quota using bad captcha.
      const linkAccepted = await backendRpc(env, fetchImpl, 'consume_checkout_gateway_quota', {
        p_digest: linkDigest,
        p_kind: 'order_link_minute',
      })
      if (linkAccepted !== true)
        return json(429, { error: 'Trop de demandes. Réessayez plus tard.' }, allowedOrigin)

      const result = await backendRpc(env, fetchImpl, 'submit_checkout_public_order', {
        p_token: token,
        p_channel: body.channel,
        p_operation_id: body.operationId,
        p_lines: body.lines,
        p_customer_phone: body.phone?.trim() || null,
        p_customer_note: body.note?.trim() || null,
        p_fulfillment: body.fulfillment,
        p_payment_method: body.paymentMethod ?? 'cash',
        p_delivery_address: body.fulfillment === 'delivery' ? body.deliveryAddress?.trim() : null,
      })
      if (
        !result ||
        !UUID.test(result.orderId) ||
        !UUID.test(result.trackingToken) ||
        !UUID.test(result.shopId) ||
        !['submitted', 'approved', 'reserved', 'paid', 'cancelled', 'expired'].includes(
          result.status,
        ) ||
        !Number.isSafeInteger(result.amountXaf) ||
        result.amountXaf < 0 ||
        result.amountXaf > 2000000000
      ) throw new Error('order')
      if (body.referenceImage) {
        await saveCheckoutReference(env, fetchImpl, result, body)
      }
      return json(200, {
        orderId: result.orderId,
        status: result.status,
        amountXaf: result.amountXaf,
        trackingToken: result.trackingToken,
      }, allowedOrigin)
    } catch {
      // No database, token, key, IP, phone or provider error details in responses.
      return json(503, { error: 'Service temporairement indisponible.' }, allowedOrigin)
    }
  }
}
