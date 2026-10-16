// Purge nocturne des comptes dont la suppression a été demandée il y a 30 jours ou plus.
// Exécutable dans Deno (fonction Edge Supabase) et dans Node (tests Vitest).
//
// Appelée chaque nuit par pg_cron (en-tête x-covi-purge-token, jeton gardé dans Vault). Pour
// chaque compte dû : efface les photos du stockage (produits et commandes de ses boutiques, photo
// de profil), efface ses boutiques et tout leur contenu (account_purge_shops), puis supprime le
// compte (API d'administration). Un compte qui échoue est retenté la nuit suivante.
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const SHOP_BUCKETS = ['covi-product-images', 'covi-order-references']
const PROFILE_BUCKET = 'covi-profile-photos'

const json = (status, data) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' },
  })

export function createAccountPurgeHandler(env, fetchImpl = fetch) {
  const headers = (type = 'application/json') => ({
    apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: 'Bearer ' + env.SUPABASE_SERVICE_ROLE_KEY,
    'Content-Type': type,
  })
  const url = (path) => new URL(path, env.SUPABASE_URL)

  async function rpc(name, args) {
    const res = await fetchImpl(url('/rest/v1/rpc/' + name), {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify(args),
    })
    const body = await res.json().catch(() => null)
    if (!res.ok) throw new Error((body && body.message) || 'rpc ' + name + ' ' + res.status)
    return body
  }

  async function list(bucket, folder) {
    const res = await fetchImpl(url('/storage/v1/object/list/' + bucket), {
      method: 'POST',
      headers: headers(),
      body: JSON.stringify({ prefix: folder, limit: 100, offset: 0 }),
    })
    if (!res.ok) throw new Error('list ' + bucket + ' ' + res.status)
    return ((await res.json()) || []).filter(
      (o) => o && typeof o.name === 'string' && o.name && !o.name.includes('/'),
    )
  }

  /**
   * Efface tous les fichiers d'un dossier (« <id>/… ») et de ses sous-dossiers (une commande
   * range sa photo dans « <boutique>/<commande>/reference.jpg »), par paquets de 100.
   */
  async function clearFolder(bucket, folder, depth = 0) {
    let removed = 0
    for (let round = 0; round < 50; round++) {
      const entries = await list(bucket, folder)
      // Un sous-dossier n'a pas d'id : on le vide d'abord, il disparaît avec son dernier fichier.
      for (const sub of entries.filter((o) => !o.id))
        if (depth < 3) removed += await clearFolder(bucket, folder + '/' + sub.name, depth + 1)
      const names = entries.filter((o) => o.id).map((o) => o.name)
      if (names.length === 0) return removed
      const del = await fetchImpl(url('/storage/v1/object/' + bucket), {
        method: 'DELETE',
        headers: headers(),
        body: JSON.stringify({ prefixes: names.map((n) => folder + '/' + n) }),
      })
      if (!del.ok) throw new Error('delete ' + bucket + ' ' + del.status)
      removed += names.length
    }
    return removed
  }

  return async function handle(req) {
    if (req.method !== 'POST') return json(405, { error: 'POST only' })
    const token = req.headers.get('x-covi-purge-token') || ''
    if (!env.SUPABASE_URL || !env.SUPABASE_SERVICE_ROLE_KEY) return json(503, { error: 'config' })
    if (!/^[0-9a-f]{64}$/.test(token)) return json(401, { error: 'unauthorized' })
    let due
    try {
      due = await rpc('account_purge_due', { p_token: token })
    } catch {
      return json(401, { error: 'unauthorized' })
    }
    const done = []
    const failed = []
    for (const entry of Array.isArray(due) ? due : []) {
      const userId = entry && entry.user_id
      if (!UUID.test(String(userId))) continue
      const shopIds = (entry.shop_ids || []).filter((id) => UUID.test(String(id)))
      try {
        let files = 0
        for (const shopId of shopIds)
          for (const bucket of SHOP_BUCKETS) files += await clearFolder(bucket, shopId)
        files += await clearFolder(PROFILE_BUCKET, userId)
        await rpc('account_purge_shops', { p_token: token, p_user_id: userId })
        const res = await fetchImpl(url('/auth/v1/admin/users/' + userId), {
          method: 'DELETE',
          headers: headers(),
        })
        if (!res.ok && res.status !== 404) throw new Error('auth delete ' + res.status)
        done.push({ userId, shops: shopIds.length, files })
      } catch (e) {
        failed.push({ userId, error: String((e && e.message) || e).slice(0, 200) })
      }
    }
    return json(failed.length ? 207 : 200, { purged: done.length, done, failed })
  }
}
