function json(status, body) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
  })
}

function isoDateInTimeZone(timeZone, now = new Date()) {
  return new Intl.DateTimeFormat('en-CA', { timeZone }).format(now)
}

function safeArray(value) {
  return Array.isArray(value) ? value : []
}

export function createDailyReportHandler({ fetchImpl = fetch, env = {} } = {}) {
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
    return response.json()
  }

  return async function handler(request) {
    if (request.method !== 'POST') return json(405, { error: 'Method not allowed' })
    try {
      const body = await request.json().catch(() => ({}))
      const shopId = typeof body.shop_id === 'string' ? body.shop_id : ''
      if (!shopId) return json(400, { error: 'shop_id is required' })

      const [shop, dashboard, stock, movements, charges] = await Promise.all([
        db(`/rest/v1/shops?id=eq.${encodeURIComponent(shopId)}&select=id,name,currency,business_kind`),
        db('/rest/v1/rpc/shop_dashboard', {
          method: 'POST',
          body: JSON.stringify({ p_shop_id: shopId, p_tz: body.timezone ?? 'Africa/Brazzaville', p_include_test: false }),
        }),
        db(`/rest/v1/products?shop_id=eq.${encodeURIComponent(shopId)}&is_test=eq.false&status=eq.active&select=name,quantity_on_hand&order=quantity_on_hand.asc&limit=100`),
        db(`/rest/v1/stock_movements?shop_id=eq.${encodeURIComponent(shopId)}&select=movement_type,quantity,created_at&order=created_at.desc&limit=100`),
        db(`/rest/v1/shop_expenses?shop_id=eq.${encodeURIComponent(shopId)}&select=amount,category,created_at&order=created_at.desc&limit=100`),
      ])

      const currentShop = shop?.[0]
      if (!currentShop) return json(404, { error: 'Shop not found' })
      const timezone = typeof body.timezone === 'string' ? body.timezone : 'Africa/Brazzaville'
      const reportDate = isoDateInTimeZone(timezone)
      const lowStock = safeArray(stock).filter((item) => Number(item.quantity_on_hand) <= 3)
      const report = {
        shop_id: shopId,
        report_date: reportDate,
        shop: currentShop,
        dashboard,
        stock: { remaining_products: safeArray(stock).length, low_stock: lowStock },
        movements: safeArray(movements),
        charges: safeArray(charges),
      }

      await db('/rest/v1/whatsapp_daily_reports?on_conflict=shop_id,report_date', {
        method: 'POST',
        headers: { prefer: 'resolution=merge-duplicates,return=minimal' },
        body: JSON.stringify({ shop_id: shopId, report_date: reportDate, payload: report, status: 'queued' }),
      })
      const preferences = await db(
        `/rest/v1/whatsapp_notification_preferences?shop_id=eq.${encodeURIComponent(shopId)}&select=enabled,daily_report_enabled,recipient_phone`,
      )
      const preference = preferences?.[0]
      if (preference?.enabled && preference.daily_report_enabled && preference.recipient_phone) {
        await db('/rest/v1/whatsapp_outbox?on_conflict=shop_id,idempotency_key', {
          method: 'POST',
          headers: { prefer: 'resolution=ignore-duplicates,return=minimal' },
          body: JSON.stringify({
            shop_id: shopId,
            event_type: 'daily_report',
            idempotency_key: `daily_report:${reportDate}`,
            recipient_phone: preference.recipient_phone,
            template_name: body.template_name ?? 'covi_daily_report',
            payload: { language: 'fr', report },
            status: 'queued',
          }),
        })
      }
      return json(200, { report })
    } catch {
      return json(503, { error: 'Daily report generation unavailable' })
    }
  }
}
