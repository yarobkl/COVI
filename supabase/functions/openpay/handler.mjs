// Paiement Mobile Money (MTN, Airtel) des commandes COVI via OpenPay (openpay.cg).
// Exécutable dans Deno (fonction Edge Supabase) et dans Node (tests Vitest).
//
// Trois actions :
//   request  (boutique connectée) : crée la demande en base avec le JWT de la boutique, puis
//            demande le paiement à OpenPay avec la clé API de CETTE boutique (lue dans Vault).
//   refresh  (boutique connectée) : relit le statut chez OpenPay.
//   callback (OpenPay)            : OpenPay prévient COVI. Le callback n'est pas signé : COVI ne
//            croit jamais son contenu et RELIT toujours le statut chez OpenPay avec la clé.
// Un paiement n'est « reçu » que si OpenPay le dit au statut relu ET pour le montant demandé.
// Aucune vente ni aucun stock n'est modifié ici : la vente reste confirmée en caisse.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PROVIDERS = ['MTN', 'AIRTEL']
const OPENPAY_STATUSES = ['pending', 'success', 'failed', 'cancelled']
const jsonHeaders = {
  'Content-Type': 'application/json; charset=utf-8',
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
}

const ERRORS = {
  'OpenPay not configured': 'Ajoutez d’abord la clé OpenPay de la boutique (Commandes → QR & liens).',
  'Mobile payment already pending':
    'Une demande de paiement est déjà en cours pour cette commande. Attendez la réponse du client.',
  'Mobile payment already received': 'Cette commande est déjà payée par Mobile Money.',
  'Order already closed': 'Cette commande est déjà clôturée.',
  'Invalid mobile money phone': 'Numéro Mobile Money invalide (format 06 XXX XX XX).',
  'Invalid mobile money provider': 'Choisissez MTN ou Airtel.',
  'Invalid mobile money amount': 'Montant invalide.',
  'Order not found': 'Commande introuvable.',
  'Payment not found': 'Paiement introuvable.',
  'Shop not found': 'Action réservée à la boutique.',
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

function origins(value) {
  return String(value ?? '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
}

/** Numéro congolais au format OpenPay : 242 suivi de 9 chiffres. */
export function normalizeCongoPhone(value) {
  const digits = String(value ?? '').replace(/\D/g, '')
  if (/^242\d{9}$/.test(digits)) return digits
  if (/^0\d{8}$/.test(digits)) return '242' + digits
  return null
}

function serviceHeaders(env) {
  const key = env.SUPABASE_SERVICE_ROLE_KEY
  return {
    apikey: key,
    ...(key.startsWith('eyJ') ? { Authorization: 'Bearer ' + key } : {}),
    'Content-Type': 'application/json',
  }
}

async function callRpc(env, fetchImpl, name, payload, headers) {
  const response = await fetchImpl(new URL('/rest/v1/rpc/' + name, env.SUPABASE_URL), {
    method: 'POST',
    headers,
    body: JSON.stringify(payload),
  })
  if (!response.ok) {
    const error = new Error('backend')
    error.status = response.status
    try {
      error.detail = (await response.json())?.message ?? null
    } catch {
      error.detail = null
    }
    throw error
  }
  return response.json()
}

const serviceRpc = (env, fetchImpl, name, payload) =>
  callRpc(env, fetchImpl, name, payload, serviceHeaders(env))

const userRpc = (env, fetchImpl, jwt, name, payload) =>
  callRpc(env, fetchImpl, name, payload, {
    apikey: env.SUPABASE_ANON_KEY,
    Authorization: 'Bearer ' + jwt,
    'Content-Type': 'application/json',
  })

function openPayUrl(env, path) {
  return new URL(path, env.OPENPAY_API_BASE || 'https://api.openpay-cg.com')
}

/** Statut relu chez OpenPay, jamais celui reçu dans un callback. */
async function fetchOpenPayStatus(env, fetchImpl, apiKey, reference) {
  const response = await fetchImpl(
    openPayUrl(env, '/v1/transaction/status/' + encodeURIComponent(reference)),
    { method: 'GET', headers: { 'XO-API-KEY': apiKey, Accept: 'application/json' } },
  )
  if (!response.ok) {
    const error = new Error('openpay')
    error.status = response.status
    throw error
  }
  return response.json()
}

/** Statut COVI d'après la réponse OpenPay : « success » seulement pour le montant demandé. */
export function coviStatus(openpay, expectedAmount) {
  const raw = String(openpay?.status ?? '').toLowerCase()
  const status = OPENPAY_STATUSES.includes(raw) ? raw : 'pending'
  if (status === 'success' && Number(openpay?.amount) !== Number(expectedAmount)) {
    return { status: 'error', message: 'Montant reçu différent du montant demandé.' }
  }
  return { status, message: typeof openpay?.message === 'string' ? openpay.message : null }
}

async function refreshPayment(env, fetchImpl, paymentId) {
  const ctx = await serviceRpc(env, fetchImpl, 'openpay_payment_context', {
    p_payment_id: paymentId,
  })
  if (!ctx) return { status: 'error', message: 'OpenPay n’est pas configuré pour cette boutique.' }
  if (!ctx.reference || !['requested', 'pending'].includes(ctx.status)) {
    return { paymentId, status: ctx.status, reference: ctx.reference ?? null }
  }
  const remote = await fetchOpenPayStatus(env, fetchImpl, ctx.apiKey, ctx.reference)
  const next = coviStatus(remote, ctx.amount)
  const status = await serviceRpc(env, fetchImpl, 'record_openpay_status', {
    p_payment_id: paymentId,
    p_reference: ctx.reference,
    p_status: next.status,
    p_message: next.message,
  })
  return { paymentId, status, reference: ctx.reference }
}

export function createOpenPayHandler(env, fetchImpl = fetch) {
  return async function handle(request) {
    const url = new URL(request.url)
    const action = url.searchParams.get('action')
    const origin = request.headers.get('origin')
    const allowed = origin && origins(env.COVI_PUBLIC_ORIGIN).includes(origin) ? origin : null
    const configured =
      env.COVI_OPENPAY_ENABLED !== 'false' &&
      typeof env.SUPABASE_URL === 'string' &&
      typeof env.SUPABASE_SERVICE_ROLE_KEY === 'string' &&
      env.SUPABASE_SERVICE_ROLE_KEY.length > 20

    if (request.method === 'OPTIONS') {
      if (!allowed) return new Response(null, { status: 403 })
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': allowed,
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'content-type, authorization, apikey, x-client-info',
          'Access-Control-Max-Age': '600',
          Vary: 'Origin',
        },
      })
    }
    if (request.method !== 'POST') return json(405, { error: 'Méthode interdite.' }, allowed)

    // Callback OpenPay (serveur à serveur, sans origine navigateur). -----------------------------
    if (action === 'callback') {
      if (!configured) return json(503, { success: false }, null)
      let body
      try {
        body = await request.json()
      } catch {
        return json(200, { success: true, ignored: true }, null)
      }
      const reference = typeof body?.reference === 'string' ? body.reference.slice(0, 120) : ''
      if (!reference || body?.type === 'scheduled_cashout') {
        return json(200, { success: true, ignored: true }, null)
      }
      try {
        const paymentId = await serviceRpc(env, fetchImpl, 'openpay_payment_by_reference', {
          p_reference: reference,
        })
        if (!paymentId) return json(200, { success: true, ignored: true }, null)
        const result = await refreshPayment(env, fetchImpl, paymentId)
        return json(200, { success: true, status: result.status }, null)
      } catch {
        // Réponse ≠ 200 : OpenPay réessaie (5 s, 15 s, 30 s).
        return json(502, { success: false }, null)
      }
    }

    // Actions de la boutique : origine COVI et session de la boutique. ---------------------------
    if (!allowed) return json(403, { error: 'Origine non autorisée.' }, null)
    if (!configured) {
      return json(503, { error: 'Le paiement Mobile Money est momentanément indisponible.' }, allowed)
    }
    const jwt = (request.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
    if (!jwt || jwt.split('.').length !== 3) {
      return json(401, { error: 'Connectez-vous à la boutique.' }, allowed)
    }
    let body
    try {
      body = await request.json()
    } catch {
      return json(400, { error: 'Requête invalide.' }, allowed)
    }

    try {
      if (action === 'request') {
        const phone = normalizeCongoPhone(body?.phone)
        const provider = String(body?.provider ?? '').toUpperCase()
        const amount = Number(body?.amount)
        if (!UUID.test(String(body?.orderId ?? ''))) {
          return json(400, { error: 'Commande invalide.' }, allowed)
        }
        if (!phone) return json(400, { error: ERRORS['Invalid mobile money phone'] }, allowed)
        if (!PROVIDERS.includes(provider)) {
          return json(400, { error: ERRORS['Invalid mobile money provider'] }, allowed)
        }
        if (!Number.isSafeInteger(amount) || amount <= 0 || amount > 10_000_000) {
          return json(400, { error: ERRORS['Invalid mobile money amount'] }, allowed)
        }
        // 1. La base vérifie la boutique, la commande et l'absence de demande en cours.
        const paymentId = await userRpc(env, fetchImpl, jwt, 'request_order_mobile_payment', {
          p_order_id: body.orderId,
          p_provider: provider,
          p_phone: phone,
          p_amount: amount,
        })
        const ctx = await serviceRpc(env, fetchImpl, 'openpay_payment_context', {
          p_payment_id: paymentId,
        })
        if (!ctx) return json(409, { error: ERRORS['OpenPay not configured'] }, allowed)
        // 2. Demande à OpenPay : le client reçoit une notification à valider sur son téléphone.
        const response = await fetchImpl(openPayUrl(env, '/v1/transaction/payment'), {
          method: 'POST',
          headers: {
            'XO-API-KEY': ctx.apiKey,
            'Content-Type': 'application/json',
            Accept: 'application/json',
          },
          body: JSON.stringify({
            amount: Number(ctx.amount),
            payment_phone_number: ctx.phone,
            provider: ctx.provider,
            customer_external_id: ctx.orderReference,
            customer: { name: ctx.customerName, phone: ctx.phone },
            metadata: { covi_payment_id: paymentId, covi_order_reference: ctx.orderReference },
          }),
        })
        let answer = null
        try {
          answer = await response.json()
        } catch {
          answer = null
        }
        const reference = typeof answer?.reference === 'string' ? answer.reference.slice(0, 120) : null
        if (!response.ok || !reference) {
          await serviceRpc(env, fetchImpl, 'record_openpay_status', {
            p_payment_id: paymentId,
            p_reference: reference,
            p_status: 'error',
            p_message: typeof answer?.message === 'string' ? answer.message : 'OpenPay a refusé la demande.',
          })
          return json(
            502,
            { error: 'OpenPay a refusé la demande. Vérifiez le numéro et la clé OpenPay.', paymentId },
            allowed,
          )
        }
        // La réponse immédiate ne vaut jamais paiement : « en attente » jusqu'au statut relu.
        await serviceRpc(env, fetchImpl, 'record_openpay_status', {
          p_payment_id: paymentId,
          p_reference: reference,
          p_status: 'pending',
          p_message: 'Demande envoyée au client.',
        })
        return json(200, { paymentId, status: 'pending', reference }, allowed)
      }

      if (action === 'refresh') {
        if (!UUID.test(String(body?.paymentId ?? ''))) {
          return json(400, { error: 'Paiement invalide.' }, allowed)
        }
        await userRpc(env, fetchImpl, jwt, 'assert_order_payment_owner', {
          p_payment_id: body.paymentId,
        })
        return json(200, await refreshPayment(env, fetchImpl, body.paymentId), allowed)
      }
    } catch (error) {
      const detail = error?.detail ?? ''
      const known = Object.keys(ERRORS).find((k) => detail.includes(k))
      if (known) return json(409, { error: ERRORS[known] }, allowed)
      if (error?.status === 401 || error?.status === 403) {
        return json(401, { error: 'Connectez-vous à la boutique.' }, allowed)
      }
      return json(502, { error: 'OpenPay ne répond pas. Réessayez dans un instant.' }, allowed)
    }
    return json(404, { error: 'Action inconnue.' }, allowed)
  }
}
