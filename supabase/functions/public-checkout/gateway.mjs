// Passerelle publique des commandes clients COVI (QR code, liens WhatsApp / TikTok).
// Exécutable dans Deno (fonction Edge Supabase) et dans Node (tests Vitest).
//
// Le client n'a pas de compte. Cette passerelle est le SEUL chemin entre le navigateur du client
// et la base : elle vérifie l'origine, l'anti-robot Cloudflare Turnstile (dépôt de commande), les
// quotas (empreintes HMAC, jamais l'IP en clair) et chaque champ, puis appelle des fonctions SQL
// réservées à la clé serveur. Aucune validation de commande, aucun encaissement, aucune écriture de
// stock n'est accessible ici. La clé serveur n'est jamais envoyée au navigateur.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const encoder = new TextEncoder()
const PAYMENT_METHODS = ['cash', 'mobile_money', 'card', 'bank_transfer']
const STATUSES = ['new', 'accepted', 'paid', 'rejected']
const MAX_BODY = 480000
const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
}

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

/** Origines autorisées : liste séparée par des virgules, chacune une origine https exacte. */
export function allowedOrigins(value) {
  return String(value ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => {
      try {
        const url = new URL(s)
        return url.origin === s && (url.protocol === 'https:' || url.hostname === 'localhost')
      } catch {
        return false
      }
    })
}

function readSettings(env) {
  const origins = allowedOrigins(env.COVI_PUBLIC_ORIGIN)
  let apiOk = false
  try {
    const api = new URL(env.SUPABASE_URL)
    apiOk = api.protocol === 'https:' && api.pathname === '/'
  } catch {
    apiOk = false
  }
  const key = env.SUPABASE_SERVICE_ROLE_KEY
  const base =
    env.COVI_GATEWAY_ENABLED === 'true' &&
    origins.length > 0 &&
    apiOk &&
    typeof key === 'string' &&
    key.length > 30 &&
    typeof env.COVI_GATEWAY_PEPPER === 'string' &&
    env.COVI_GATEWAY_PEPPER.length >= 32
  // Sans clé secrète Turnstile, la consultation reste possible mais aucun dépôt n'est accepté.
  const ordersOk =
    base && typeof env.COVI_TURNSTILE_SECRET === 'string' && env.COVI_TURNSTILE_SECRET.length >= 16
  return { origins, base, ordersOk }
}

const hasControl = (value) => /[\u0000-\u0008\u000b-\u001f\u007f]/.test(value)

function cleanText(value, max, { required = false, multiline = false } = {}) {
  if (value == null || value === '') return required ? undefined : null
  if (typeof value !== 'string') return undefined
  const text = value.trim()
  if (!text) return required ? undefined : null
  if (text.length > max) return undefined
  if (multiline ? hasControl(text) : /[\u0000-\u001f\u007f]/.test(text)) return undefined
  return text
}

/** Photo de référence : JPEG re-encodé par le canvas du navigateur.
 * Vérifie aussi structure minimale, dimensions et métadonnées avant un upload
 * avec les privilèges du serveur. Ne décode pas les pixels.
 */
function safeReferenceJpeg(bytes) {
  const length = bytes.length
  if (length < 20 || length > 300000 ||
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
    // Metadata: EXIF/XMP, IPTC/Photoshop and comments are never accepted.
    // Canvas JPEG encoding normally drops these fields.
    if ([0xe1, 0xed, 0xfe].includes(marker)) return false
    if (marker === 0x00 || marker === 0xd8 || marker === 0xd9 ||
        marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) return false
    if (offset + 2 > length - 2) return false
    const segmentLength = bytes[offset] * 256 + bytes[offset + 1]
    if (segmentLength < 2 || offset + segmentLength > length - 2) return false
    const frame = marker >= 0xc0 && marker <= 0xcf &&
      ![0xc4, 0xc8, 0xcc].includes(marker)
    if (frame) {
      if (frameSeen || segmentLength < 8) return false
      const height = bytes[offset + 3] * 256 + bytes[offset + 4]
      const width = bytes[offset + 5] * 256 + bytes[offset + 6]
      if (height < 1 || width < 1 || height > 4096 || width > 4096 ||
          height * width > 4000000) return false
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

export function decodeReferenceJpeg(value) {
  if (typeof value !== 'string' || value.length > 420000) return null
  const match = /^data:image\/jpeg;base64,([A-Za-z0-9+/]+={0,2})$/.exec(value)
  if (!match) return null
  try {
    const binary = atob(match[1])
    if (binary.length > 300000) return null
    const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0))
    return safeReferenceJpeg(bytes) ? bytes : null
  } catch {
    return null
  }
}

/** Demande normalisée, ou null si un champ est invalide. */
export function parseOrder(body) {
  if (!body || typeof body !== 'object' || Array.isArray(body)) return null
  if (!UUID.test(body.token ?? '') || !UUID.test(body.operationId ?? '')) return null
  if (!['qr', 'social'].includes(body.channel)) return null
  if (!['pickup', 'delivery'].includes(body.fulfillment)) return null
  if (!PAYMENT_METHODS.includes(body.paymentMethod)) return null
  if (typeof body.challenge !== 'string' || body.challenge.length < 10) return null
  if (body.challenge.length > 4096 || hasControl(body.challenge)) return null
  const customerName = cleanText(body.customerName, 60, { required: true })
  const phone = cleanText(body.phone, 32, { required: true })
  const address = cleanText(body.deliveryAddress, 240)
  const note = cleanText(body.note, 500, { multiline: true })
  if (!customerName || !phone || !/^\+?[0-9 ().-]{6,32}$/.test(phone)) return null
  if (address === undefined || note === undefined) return null
  if (body.fulfillment === 'delivery' && !address) return null
  if (body.referenceImage != null && !decodeReferenceJpeg(body.referenceImage)) return null
  if (!Array.isArray(body.lines) || body.lines.length < 1 || body.lines.length > 20) return null
  const lines = []
  const seen = new Set()
  for (const line of body.lines) {
    if (!line || typeof line !== 'object' || Array.isArray(line)) return null
    const quantity = line.quantity
    if (!Number.isSafeInteger(quantity) || quantity < 1 || quantity > 20) return null
    const out = { quantity }
    if (line.proposedUnitPriceXaf != null) {
      const p = line.proposedUnitPriceXaf
      if (!Number.isSafeInteger(p) || p < 1 || p > 999999999) return null
      out.proposedUnitPriceXaf = p
    }
    if (line.productId != null) {
      if (!UUID.test(line.productId) || seen.has(line.productId.toLowerCase())) return null
      seen.add(line.productId.toLowerCase())
      out.productId = line.productId.toLowerCase()
    } else {
      const description = cleanText(line.description, 120, { required: true })
      if (!description) return null
      out.description = description
    }
    lines.push(out)
  }
  return {
    token: body.token.toLowerCase(),
    operationId: body.operationId.toLowerCase(),
    channel: body.channel,
    customerName,
    phone,
    fulfillment: body.fulfillment,
    deliveryAddress: body.fulfillment === 'delivery' ? address : null,
    paymentMethod: body.paymentMethod,
    note,
    lines,
    referenceImage: body.referenceImage ?? null,
    challenge: body.challenge,
  }
}

async function limitedJson(request) {
  const length = Number(request.headers.get('content-length'))
  if (Number.isFinite(length) && length > MAX_BODY) throw new Error('size')
  const reader = request.body?.getReader()
  if (!reader) throw new Error('body')
  const parts = []
  let size = 0
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    size += value.byteLength
    if (size > MAX_BODY) {
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
  return [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

function sourceAddress(request) {
  // Au mieux : l'en-tête peut être falsifié. Turnstile et les plafonds par lien restent obligatoires.
  const raw =
    request.headers.get('cf-connecting-ip') ||
    request.headers.get('x-forwarded-for')?.split(',')[0]?.trim()
  if (!raw || raw.length > 64 || !/^[0-9a-fA-F:.]+$/.test(raw)) return 'unknown'
  return raw
}

function serverHeaders(env, contentType = 'application/json') {
  const key = env.SUPABASE_SERVICE_ROLE_KEY
  return {
    apikey: key,
    // Les anciennes clés service_role sont des JWT ; les clés sb_secret_ passent seulement en apikey.
    ...(key.startsWith('eyJ') ? { Authorization: 'Bearer ' + key } : {}),
    'Content-Type': contentType,
  }
}

async function rpc(env, fetchImpl, name, payload) {
  const response = await fetchImpl(new URL('/rest/v1/rpc/' + name, env.SUPABASE_URL), {
    method: 'POST',
    headers: serverHeaders(env),
    body: JSON.stringify(payload),
  })
  if (!response.ok) {
    const error = new Error('backend')
    error.status = response.status
    try {
      error.detail = (await response.json())?.message
    } catch {
      error.detail = null
    }
    throw error
  }
  return response.json()
}

async function verifyTurnstile(env, fetchImpl, challenge, hostnames) {
  const response = await fetchImpl('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
    method: 'POST',
    body: new URLSearchParams({ secret: env.COVI_TURNSTILE_SECRET, response: challenge }),
  })
  if (!response.ok) return false
  const outcome = await response.json()
  return (
    outcome?.success === true &&
    hostnames.includes(outcome.hostname) &&
    outcome.action === 'covi_order'
  )
}

async function storeReference(env, fetchImpl, order, result) {
  const image = decodeReferenceJpeg(order.referenceImage)
  if (!image) return false
  const path = await rpc(env, fetchImpl, 'attach_public_order_reference', {
    p_token: order.token,
    p_order_id: result.orderId,
    p_operation_id: order.operationId,
  })
  if (typeof path !== 'string' || !path.startsWith(result.shopId + '/')) return false
  const upload = await fetchImpl(
    new URL('/storage/v1/object/covi-order-references/' + path, env.SUPABASE_URL),
    {
      method: 'POST',
      headers: { ...serverHeaders(env, 'image/jpeg'), 'x-upsert': 'false' },
      body: image,
    },
  )
  // Un nouvel essai ne remplace jamais une photo déjà déposée.
  return upload.ok || upload.status === 409
}

const CUSTOMER_ERRORS = {
  'Product unavailable': 'Un article n’est plus disponible. Actualisez la page et choisissez de nouveau.',
  'Insufficient stock': 'La quantité demandée dépasse le stock disponible.',
  'Order link unavailable': 'Ce lien de commande n’est plus actif. Demandez un nouveau lien à la boutique.',
}

export function createPublicCheckoutGateway(env, fetchImpl = fetch) {
  return async function handle(request) {
    const settings = readSettings(env)
    const origin = request.headers.get('origin')
    const allowed = origin && settings.origins.includes(origin) ? origin : null
    if (!allowed) return json(403, { error: 'Origine non autorisée.' }, null)
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': allowed,
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'content-type, apikey, authorization, x-client-info',
          'Access-Control-Max-Age': '600',
          Vary: 'Origin',
        },
      })
    }
    if (request.method !== 'GET' && request.method !== 'POST')
      return json(405, { error: 'Méthode interdite.' }, allowed)
    if (!settings.base)
      return json(503, { error: 'Les commandes en ligne sont momentanément fermées.' }, allowed)

    try {
      const url = new URL(request.url)
      const source = sourceAddress(request)

      if (request.method === 'GET') {
        const tracking = url.searchParams.get('tracking')
        const token = url.searchParams.get('token')
        const isTracking = tracking != null
        const key = (isTracking ? tracking : token) ?? ''
        if (!UUID.test(key)) return json(400, { error: 'Lien invalide.' }, allowed)
        const sourceDigest = await hmac(env.COVI_GATEWAY_PEPPER, 'source:' + source)
        const keyDigest = await hmac(env.COVI_GATEWAY_PEPPER, 'key:' + key.toLowerCase())
        const quotas = isTracking
          ? [
              ['status_source_minute', sourceDigest],
              ['status_token_minute', keyDigest],
            ]
          : [
              ['catalog_source_minute', sourceDigest],
              ['catalog_link_minute', keyDigest],
            ]
        for (const [kind, digest] of quotas) {
          if ((await rpc(env, fetchImpl, 'consume_public_order_quota', { p_digest: digest, p_kind: kind })) !== true)
            return json(429, { error: 'Trop de demandes. Réessayez dans une minute.' }, allowed)
        }
        if (isTracking) {
          const status = await rpc(env, fetchImpl, 'get_public_order_status', {
            p_tracking_token: key.toLowerCase(),
          })
          if (!status) return json(404, { error: 'Commande introuvable.' }, allowed)
          if (!STATUSES.includes(status.status)) throw new Error('status')
          return json(200, status, allowed)
        }
        const catalog = await rpc(env, fetchImpl, 'get_public_order_catalog', {
          p_token: key.toLowerCase(),
        })
        if (!catalog)
          return json(404, { error: 'Ce lien de commande n’est plus actif.' }, allowed)
        if (typeof catalog.shopName !== 'string' || !Array.isArray(catalog.products))
          throw new Error('catalog')
        return json(200, { ...catalog, ordersOpen: settings.ordersOk }, allowed)
      }

      // POST : dépôt d'une demande.
      if (!settings.ordersOk)
        return json(503, { error: 'Les commandes en ligne sont momentanément fermées.' }, allowed)
      if (!request.headers.get('content-type')?.toLowerCase().startsWith('application/json'))
        return json(415, { error: 'Format non pris en charge.' }, allowed)
      let body
      try {
        body = await limitedJson(request)
      } catch {
        return json(400, { error: 'Demande invalide ou photo trop lourde.' }, allowed)
      }
      const order = parseOrder(body)
      if (!order) return json(400, { error: 'Vérifiez les informations saisies.' }, allowed)

      const sourceDigest = await hmac(env.COVI_GATEWAY_PEPPER, 'source:' + source)
      for (const kind of ['order_source_minute', 'order_source_day']) {
        if ((await rpc(env, fetchImpl, 'consume_public_order_quota', { p_digest: sourceDigest, p_kind: kind })) !== true)
          return json(429, { error: 'Trop de demandes. Réessayez plus tard.' }, allowed)
      }
      const hostnames = settings.origins.map((o) => new URL(o).hostname)
      if (!(await verifyTurnstile(env, fetchImpl, order.challenge, hostnames)))
        return json(403, { error: 'Vérification anti-robot non validée. Réessayez.' }, allowed)
      // Le plafond de la boutique n'est consommé qu'après l'anti-robot : un robot ne peut pas
      // épuiser le canal d'une boutique.
      const linkDigest = await hmac(env.COVI_GATEWAY_PEPPER, 'key:' + order.token)
      for (const kind of ['order_link_minute', 'order_link_day']) {
        if ((await rpc(env, fetchImpl, 'consume_public_order_quota', { p_digest: linkDigest, p_kind: kind })) !== true)
          return json(429, { error: 'La boutique reçoit trop de demandes. Réessayez plus tard.' }, allowed)
      }

      let result
      try {
        result = await rpc(env, fetchImpl, 'submit_public_order', {
          p_token: order.token,
          p_channel: order.channel,
          p_operation_id: order.operationId,
          p_customer_name: order.customerName,
          p_customer_phone: order.phone,
          p_fulfillment: order.fulfillment,
          p_delivery_address: order.deliveryAddress,
          p_payment_method: order.paymentMethod,
          p_note: order.note,
          p_lines: order.lines,
        })
      } catch (error) {
        const message = CUSTOMER_ERRORS[error?.detail]
        if (message) return json(409, { error: message }, allowed)
        throw error
      }
      if (!result || !UUID.test(result.orderId) || !UUID.test(result.trackingToken))
        throw new Error('order')
      let photoSaved = null
      if (order.referenceImage) {
        try {
          photoSaved = await storeReference(env, fetchImpl, order, result)
        } catch {
          photoSaved = false
        }
      }
      return json(
        200,
        {
          reference: result.reference,
          status: result.status,
          amountXaf: result.amountXaf,
          trackingToken: result.trackingToken,
          photoSaved,
        },
        allowed,
      )
    } catch {
      // Jamais de détail technique (base, clé, IP, téléphone) dans la réponse.
      return json(503, { error: 'Service momentanément indisponible. Réessayez.' }, allowed)
    }
  }
}
