// Pure Web Push dispatcher. Injected dependencies make authorization, SSRF and retries testable.
export const trustedPushEndpoint = (input) => {
  try {
    if (typeof input !== 'string' || input.length < 50 || input.length > 1500) return false
    const url = new URL(input)
    if (url.protocol !== 'https:' || url.username || url.password ||
        url.port || url.hash || !url.pathname || url.pathname === '/') return false
    const host = url.hostname.toLowerCase()
    return host === 'fcm.googleapis.com' ||
      host === 'updates.push.services.mozilla.com' ||
      host === 'web.push.apple.com' ||
      /^[a-z0-9-]+\.push\.apple\.com$/.test(host) ||
      /^[a-z0-9-]+\.notify\.windows\.com$/.test(host)
  } catch { return false }
}

export function constantTimeTokenEquals(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false
  const left = new TextEncoder().encode(a)
  const right = new TextEncoder().encode(b)
  let mismatch = left.length ^ right.length
  const n = Math.max(left.length, right.length)
  for (let i = 0; i < n; i++) mismatch |= (left[i] ?? 0) ^ (right[i] ?? 0)
  return mismatch === 0
}

const json = (value, status = 200) => new Response(JSON.stringify(value), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' },
})
const validJob = (x) => x && typeof x === 'object' &&
  typeof x.id === 'string' && /^[0-9a-f-]{36}$/i.test(x.id) &&
  typeof x.lease === 'string' && /^[0-9a-f-]{36}$/i.test(x.lease) &&
  typeof x.through === 'string' && /^[1-9][0-9]{0,18}$/.test(x.through) &&
  Number.isInteger(x.count) && x.count >= 1 && x.count <= 999 &&
  typeof x.endpoint === 'string' &&
  typeof x.p256dh === 'string' && /^[A-Za-z0-9_-]{40,255}$/.test(x.p256dh) &&
  typeof x.auth === 'string' && /^[A-Za-z0-9_-]{12,128}$/.test(x.auth)

export function createKitchenPushDispatcher(config, { rpc, sendPush }) {
  return async (request) => {
    if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)
    if (config.enabled !== 'true') return json({ error: 'disabled' }, 503)
    if (!config.secret || config.secret.length < 32 || !config.publicKey ||
        !config.privateKey || !config.subject || !config.serviceKey)
      return json({ error: 'not_configured' }, 503)
    const token = request.headers.get('authorization')?.match(/^Bearer[ \t]+([^\s]+)$/i)?.[1] ?? ''
    if (!constantTimeTokenEquals(token, config.secret))
      return json({ error: 'unauthorized' }, 401)
    let tasks
    try { tasks = await rpc('restaurant_kitchen_push_claim', { p_limit: 25 }) }
    catch { return json({ error: 'queue_unavailable' }, 503) }
    if (!Array.isArray(tasks) || tasks.length > 25)
      return json({ error: 'invalid_queue_response' }, 503)
    const stats = { claimed: tasks.length, sent: 0, gone: 0, retry: 0, failedAcks: 0 }
    for (const task of tasks) {
      if (!validJob(task)) {
        stats.failedAcks++
        // Never send to malformed destinations. Lease will expire for operator review.
        continue
      }
      let outcome = 'retry'
      try {
        if (!trustedPushEndpoint(task.endpoint)) {
          outcome = 'gone'
        } else {
          // Generic text only: nothing about guests, payments, dishes or specific restaurants.
          await sendPush(
            { endpoint: task.endpoint, keys: { p256dh: task.p256dh, auth: task.auth } },
            JSON.stringify({
              title: 'COVI — Nouvelle préparation',
              body: task.count === 1
                ? 'Un nouvel article attend la cuisine.'
                : 'De nouvelles préparations attendent la cuisine.',
            }),
          )
          outcome = 'sent'
        }
      } catch (error) {
        // 404/410: expired or removed push subscription. Never retry that endpoint.
        outcome = error?.statusCode === 404 || error?.statusCode === 410 ? 'gone' : 'retry'
      }
      try {
        const ok = await rpc('restaurant_kitchen_push_finish', {
          p_id: task.id, p_lease: task.lease,
          p_through: task.through, p_outcome: outcome,
        })
        if (ok !== true) throw Error('delivery lease changed')
        stats[outcome]++
      } catch {
        // On ack failure: do not claim success, retries might duplicate; browser tag collapses.
        stats.failedAcks++
      }
    }
    return json(stats, stats.failedAcks ? 503 : 200)
  }
}
