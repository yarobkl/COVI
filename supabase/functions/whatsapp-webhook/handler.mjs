function json(status, body = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  })
}

async function validSignature(request, rawBody, appSecret) {
  if (!appSecret) return true
  const signature = request.headers.get('x-hub-signature-256') ?? ''
  const expected = signature.replace(/^sha256=/, '')
  if (!expected) return false
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(appSecret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  const digest = new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody)))
  const actual = [...digest].map((value) => value.toString(16).padStart(2, '0')).join('')
  return actual === expected
}

export function createWhatsAppWebhookHandler({ fetchImpl = fetch, env = {} } = {}) {
  async function db(path, options = {}) {
    const response = await fetchImpl(`${env.SUPABASE_URL}${path}`, {
      ...options,
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        'content-type': 'application/json',
        ...(options.headers ?? {}),
      },
    })
    if (!response.ok) throw new Error(`database request failed: ${response.status}`)
    return response.status === 204 ? null : response.json()
  }

  return async function handler(request) {
    if (request.method === 'GET') {
      const url = new URL(request.url)
      if (
        url.searchParams.get('hub.mode') === 'subscribe' &&
        url.searchParams.get('hub.verify_token') === env.WHATSAPP_VERIFY_TOKEN
      ) {
        return new Response(url.searchParams.get('hub.challenge') ?? '', { status: 200 })
      }
      return json(403, { error: 'Webhook verification failed' })
    }
    if (request.method !== 'POST') return json(405, { error: 'Method not allowed' })

    try {
      const rawBody = await request.text()
      if (!(await validSignature(request, rawBody, env.WHATSAPP_APP_SECRET))) return json(401, { error: 'Invalid signature' })
      const payload = JSON.parse(rawBody || '{}')
      const entries = Array.isArray(payload?.entry) ? payload.entry : []
      for (const entry of entries) {
        for (const change of Array.isArray(entry?.changes) ? entry.changes : []) {
          const value = change?.value ?? {}
          const phoneNumberId = value?.metadata?.phone_number_id ?? null
          for (const status of Array.isArray(value?.statuses) ? value.statuses : []) {
            const eventId = `status:${status.id}:${status.status}`
            await db('/rest/v1/whatsapp_webhook_events', {
              method: 'POST',
              headers: { prefer: 'resolution=ignore-duplicates,return=minimal' },
              body: JSON.stringify({ event_id: eventId, phone_number_id: phoneNumberId, event_type: `status.${status.status}`, payload: status, processed_at: new Date().toISOString() }),
            })
            await db(`/rest/v1/whatsapp_outbox?provider_message_id=eq.${encodeURIComponent(status.id)}`, {
              method: 'PATCH',
              headers: { prefer: 'return=minimal' },
              body: JSON.stringify({ status: status.status === 'failed' ? 'failed' : status.status }),
            })
          }
        }
      }
      return json(200, { received: true })
    } catch {
      return json(400, { error: 'Invalid webhook payload' })
    }
  }
}
