// @vitest-environment node
import { describe, expect, it } from 'vitest'
import { createAccountPurgeHandler } from '../supabase/functions/account-purge/handler.mjs'

const env = { SUPABASE_URL: 'https://example.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'sb_secret' }
const token = 'a'.repeat(64)
const user = '00000000-0000-4000-8000-0000000000d1'
const shop = '10000000-0000-4000-8000-0000000000d1'

/** Faux Supabase : enregistre chaque appel, sert des fichiers jusqu'à ce qu'ils soient effacés. */
function fakeSupabase({ due = [{ user_id: user, shop_ids: [shop] }], tokenOk = true } = {}) {
  const calls = []
  const files = {
    'covi-product-images': { [shop]: ['p1.jpg', 'p2.png'] },
    'covi-order-references': { [shop + '/order-1']: ['reference.jpg'] },
    'covi-profile-photos': { [user]: ['me.jpg'] },
  }
  const fetchImpl = async (url, init = {}) => {
    const path = new URL(url).pathname
    const body = init.body ? JSON.parse(init.body) : null
    calls.push({ path, method: init.method, body, auth: init.headers?.Authorization })
    const ok = (data) => new Response(JSON.stringify(data), { status: 200 })
    if (path === '/rest/v1/rpc/account_purge_due')
      return tokenOk
        ? ok(due)
        : new Response(JSON.stringify({ message: 'Invalid purge token' }), { status: 401 })
    if (path === '/rest/v1/rpc/account_purge_shops') return ok(1)
    const list = path.match(/^\/storage\/v1\/object\/list\/(.+)$/)
    if (list) {
      const bucket = files[list[1]]
      const own = (bucket[body.prefix] ?? []).map((name) => ({ id: name, name }))
      // Sous-dossiers non vides : listés sans id, comme le fait Supabase Storage.
      const subs = Object.keys(bucket)
        .filter((k) => k.startsWith(body.prefix + '/') && bucket[k].length > 0)
        .map((k) => ({ id: null, name: k.slice(body.prefix.length + 1) }))
      return ok([...subs, ...own])
    }
    const del = path.match(/^\/storage\/v1\/object\/([^/]+)$/)
    if (del && init.method === 'DELETE') {
      for (const p of body.prefixes) {
        const folder = p.slice(0, p.lastIndexOf('/'))
        const name = p.slice(p.lastIndexOf('/') + 1)
        files[del[1]][folder] = (files[del[1]][folder] ?? []).filter((n) => n !== name)
      }
      return ok([])
    }
    if (path === '/auth/v1/admin/users/' + user && init.method === 'DELETE') return ok({})
    return new Response('not found', { status: 404 })
  }
  return { calls, files, fetchImpl }
}

const request = (t = token) =>
  new Request('https://fn.test/account-purge', {
    method: 'POST',
    headers: { 'x-covi-purge-token': t },
  })

describe('account-purge', () => {
  it('refuses a call without the purge token', async () => {
    const fake = fakeSupabase()
    const res = await createAccountPurgeHandler(env, fake.fetchImpl)(request('nope'))
    expect(res.status).toBe(401)
    expect(fake.calls).toHaveLength(0)
  })

  it('refuses a token the database does not recognise', async () => {
    const fake = fakeSupabase({ tokenOk: false })
    const res = await createAccountPurgeHandler(env, fake.fetchImpl)(request())
    expect(res.status).toBe(401)
    expect(fake.calls.map((c) => c.path)).toEqual(['/rest/v1/rpc/account_purge_due'])
  })

  it('erases photos, then shops, then the account, in that order', async () => {
    const fake = fakeSupabase()
    const res = await createAccountPurgeHandler(env, fake.fetchImpl)(request())
    expect(res.status).toBe(200)
    const out = await res.json()
    expect(out).toMatchObject({ purged: 1, done: [{ userId: user, files: 4 }] })
    expect(fake.files['covi-product-images'][shop]).toEqual([])
    expect(fake.files['covi-order-references'][shop + '/order-1']).toEqual([])
    expect(fake.files['covi-profile-photos'][user]).toEqual([])
    const order = fake.calls.map((c) => c.path).filter((p) => !p.includes('/list/'))
    expect(order.indexOf('/rest/v1/rpc/account_purge_shops')).toBeGreaterThan(
      order.lastIndexOf('/storage/v1/object/covi-profile-photos'),
    )
    expect(order.at(-1)).toBe('/auth/v1/admin/users/' + user)
    expect(fake.calls.every((c) => c.auth === 'Bearer sb_secret')).toBe(true)
  })

  it('keeps the account for tomorrow when a step fails', async () => {
    const fake = fakeSupabase()
    const failing = async (url, init) =>
      new URL(url).pathname === '/rest/v1/rpc/account_purge_shops'
        ? new Response(JSON.stringify({ message: 'boom' }), { status: 500 })
        : fake.fetchImpl(url, init)
    const res = await createAccountPurgeHandler(env, failing)(request())
    expect(res.status).toBe(207)
    expect(await res.json()).toMatchObject({ purged: 0, failed: [{ userId: user }] })
    expect(fake.calls.some((c) => c.path.startsWith('/auth/v1/admin/users/'))).toBe(false)
  })
})
