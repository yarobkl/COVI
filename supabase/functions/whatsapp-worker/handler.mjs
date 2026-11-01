function json(status, body) {
  return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json; charset=utf-8' } })
}

export function createWhatsAppWorkerHandler({ fetchImpl = fetch, env = {} } = {}) {
  async function db(path, options = {}) {
    const response = await fetchImpl(`${env.SUPABASE_URL}${path}`, {
      ...options,
      headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY, authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'content-type': 'application/json', ...(options.headers ?? {}) },
    })
    if (!response.ok) throw new Error(`database request failed: ${response.status}`)
    return response.status === 204 ? null : response.json()
  }

  return async function handler(request) {
    if (request.method !== 'POST') return json(405, { error: 'Method not allowed' })
    try {
      const body = await request.json().catch(() => ({}))
      const limit = Math.min(Math.max(Number(body.limit ?? 20), 1), 50)
      const items = await db(`/rest/v1/whatsapp_outbox?status=eq.queued&available_at=lte.${encodeURIComponent(new Date().toISOString())}&select=id&order=created_at.asc&limit=${limit}`)
      const results = []
      for (const item of items ?? []) {
        const response = await fetchImpl(`${env.SUPABASE_URL}/functions/v1/whatsapp-send`, { method: 'POST', headers: { authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`, 'content-type': 'application/json' }, body: JSON.stringify({ outbox_id: item.id }) })
        results.push({ id: item.id, status: response.ok ? 'processed' : 'failed' })
      }
      return json(200, { processed: results.length, results })
    } catch {
      return json(503, { error: 'WhatsApp worker unavailable' })
    }
  }
}
