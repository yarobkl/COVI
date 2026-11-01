function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  })
}

export function createWhatsAppSendHandler({ fetchImpl = fetch, env = {} } = {}) {
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
    if (request.method !== 'POST') return json(405, { error: 'Method not allowed' })
    try {
      const body = await request.json().catch(() => ({}))
      const outboxId = typeof body.outbox_id === 'string' ? body.outbox_id : ''
      if (!outboxId) return json(400, { error: 'outbox_id is required' })

      const rows = await db(
        `/rest/v1/whatsapp_outbox?id=eq.${encodeURIComponent(outboxId)}&select=id,shop_id,recipient_phone,template_name,payload,status,attempts`,
      )
      const item = rows?.[0]
      if (!item) return json(404, { error: 'Notification not found' })
      if (['sent', 'delivered', 'read'].includes(item.status)) return json(200, { status: item.status })

      const connections = await db(
        `/rest/v1/whatsapp_connections?shop_id=eq.${encodeURIComponent(item.shop_id)}&status=eq.connected&select=phone_number_id`,
      )
      const connection = connections?.[0]
      const token = env.WHATSAPP_ACCESS_TOKEN
      if (!connection?.phone_number_id || !token) {
        await db(`/rest/v1/whatsapp_outbox?id=eq.${encodeURIComponent(outboxId)}`, {
          method: 'PATCH',
          headers: { prefer: 'return=minimal' },
          body: JSON.stringify({ status: 'failed', last_error: 'WhatsApp connection is not configured' }),
        })
        return json(409, { error: 'WhatsApp is not configured for this shop' })
      }

      const response = await fetchImpl(
        `https://graph.facebook.com/${env.WHATSAPP_GRAPH_VERSION ?? 'v23.0'}/${connection.phone_number_id}/messages`,
        {
          method: 'POST',
          headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
          body: JSON.stringify({
            messaging_product: 'whatsapp',
            to: item.recipient_phone,
            type: 'template',
            template: {
              name: item.template_name,
              language: { code: item.payload?.language ?? 'fr' },
              components: item.payload?.components ?? [],
            },
          }),
        },
      )
      const result = await response.json().catch(() => ({}))
      if (!response.ok) {
        await db(`/rest/v1/whatsapp_outbox?id=eq.${encodeURIComponent(outboxId)}`, {
          method: 'PATCH',
          headers: { prefer: 'return=minimal' },
          body: JSON.stringify({ status: 'failed', attempts: Number(item.attempts ?? 0) + 1, last_error: 'Meta API request failed' }),
        })
        return json(502, { error: 'WhatsApp provider rejected the message' })
      }

      const providerMessageId = result?.messages?.[0]?.id ?? null
      await db(`/rest/v1/whatsapp_outbox?id=eq.${encodeURIComponent(outboxId)}`, {
        method: 'PATCH',
        headers: { prefer: 'return=minimal' },
        body: JSON.stringify({ status: 'sent', provider_message_id: providerMessageId, sent_at: new Date().toISOString() }),
      })
      return json(200, { status: 'sent', provider_message_id: providerMessageId })
    } catch {
      return json(503, { error: 'WhatsApp send unavailable' })
    }
  }
}
