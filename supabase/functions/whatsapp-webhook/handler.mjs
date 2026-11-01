function json(status, body = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  })
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
      const payload = await request.json()
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
