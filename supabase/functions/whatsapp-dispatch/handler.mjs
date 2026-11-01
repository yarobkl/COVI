function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  })
}

const EVENT_FLAGS = {
  sale: 'sales_enabled',
  order: 'orders_enabled',
  reservation: 'appointments_enabled',
  low_stock: 'low_stock_enabled',
  stock_movement: 'stock_movements_enabled',
  daily_report: 'daily_report_enabled',
}

export function createWhatsAppDispatchHandler({ fetchImpl = fetch, env = {} } = {}) {
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
      const shopId = typeof body.shop_id === 'string' ? body.shop_id : ''
      const eventType = typeof body.event_type === 'string' ? body.event_type : ''
      const idempotencyKey = typeof body.idempotency_key === 'string' ? body.idempotency_key : ''
      if (!shopId || !eventType || !idempotencyKey) {
        return json(400, { error: 'shop_id, event_type and idempotency_key are required' })
      }

      const preferences = await db(
        `/rest/v1/whatsapp_notification_preferences?shop_id=eq.${encodeURIComponent(shopId)}&select=enabled,recipient_phone,${Object.values(EVENT_FLAGS).join(',')}`,
      )
      const preference = preferences?.[0]
      if (!preference?.enabled) return json(200, { status: 'skipped', reason: 'notifications_disabled' })
      const flag = EVENT_FLAGS[eventType]
      if (flag && preference[flag] === false) return json(200, { status: 'skipped', reason: `${eventType}_disabled` })

      const recipientPhone = typeof body.recipient_phone === 'string' && body.recipient_phone.trim()
        ? body.recipient_phone.trim()
        : preference.recipient_phone
      if (!recipientPhone) return json(422, { error: 'recipient_phone is required' })

      const rows = await db('/rest/v1/whatsapp_outbox?on_conflict=shop_id,idempotency_key', {
        method: 'POST',
        headers: { prefer: 'resolution=ignore-duplicates,return=representation' },
        body: JSON.stringify({
          shop_id: shopId,
          event_type: eventType,
          idempotency_key: idempotencyKey,
          recipient_phone: recipientPhone,
          template_name: body.template_name ?? `covi_${eventType}`,
          payload: body.payload ?? {},
          status: 'queued',
        }),
      })
      const item = rows?.[0] ?? null
      return json(202, { status: item ? 'queued' : 'already_queued', outbox_id: item?.id ?? null })
    } catch {
      return json(503, { error: 'WhatsApp dispatch unavailable' })
    }
  }
}
