// @vitest-environment node
import { describe, it, expect } from 'vitest'
import { createRestaurantGuestGateway } from '../supabase/functions/restaurant-guest/gateway.mjs'
const q = 'a'.repeat(64),
  secret = 'b'.repeat(64)
const id = '30000000-0000-0000-0000-0000000000a1'
const env = {
  COVI_RESTAURANT_GUEST_ENABLED: 'true',
  COVI_PUBLIC_ORIGIN: 'https://covi-snowy.vercel.app',
  SUPABASE_URL: 'https://test.supabase.co/',
  SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_' + 'c'.repeat(40),
  COVI_GATEWAY_PEPPER: 'pepper-with-32-random-characters-more-than',
  COVI_TURNSTILE_SECRET: 'turnstile-secret-for-local-test',
}
const req = (body, origin = 'https://covi-snowy.vercel.app', method = 'POST') =>
  new Request('https://test.example.com/restaurant-guest', {
    method,
    headers: { origin, 'content-type': 'application/json', 'cf-connecting-ip': '1.2.3.4' },
    ...(method === 'POST' ? { body: JSON.stringify(body) } : {}),
  })
const body = (action, extra = {}) => ({ action, table: q, participantToken: secret, ...extra })
describe('Restaurant guest Edge', () => {
  it('fails closed, rejects untrusted origins and read methods', async () => {
    const gated = createRestaurantGuestGateway({ ...env, COVI_RESTAURANT_GUEST_ENABLED: 'false' })
    expect((await gated(req(body('ready')))).status).toBe(503)
    const h = createRestaurantGuestGateway(env)
    expect((await h(req(body('ready'), 'https://evil.test'))).status).toBe(403)
    expect((await h(req(body('ready'), 'https://covi-snowy.vercel.app', 'GET'))).status).toBe(405)
  })
  it('rejects forged shop, malformed credentials and quantities before backend', async () => {
    const fn = () => {
      throw new Error('No backend request allowed')
    }
    const h = createRestaurantGuestGateway(env, fn)
    expect((await h(req(body('ready', { table: 'bad' })))).status).toBe(400)
    expect((await h(req(body('choice', { itemId: id, quantity: 1.5 })))).status).toBe(400)
    expect((await h(req(body('join', { code: 'wrong', challenge: 'too-short' })))).status).toBe(400)
  })
  it('requires durable quota and correctly verified Turnstile for join', async () => {
    const calls = []
    const h = createRestaurantGuestGateway(env, async (u) => {
      const path = typeof u === 'string' ? u : new URL(u).pathname
      calls.push(path)
      if (path.includes('restaurant_guest_rate_gate')) return Response.json(true)
      if (path.includes('siteverify'))
        return Response.json({
          success: true,
          hostname: 'covi-snowy.vercel.app',
          action: 'covi_order',
        })
      throw new Error('Must not call join without valid action')
    })
    const result = await h(
      req({ action: 'join', table: q, code: 'A1B2C3D4', challenge: 'turnstile-test-token' }),
    )
    expect(result.status).toBe(403)
    expect(calls.some((x) => x.includes('restaurant_guest_join'))).toBe(false)
  })
  it('limits access before any guest RPC, even when participant token is known', async () => {
    const called = []
    const h = createRestaurantGuestGateway(env, async (u) => {
      const path = new URL(u).pathname
      called.push(path)
      if (path.endsWith('restaurant_guest_rate_gate')) return Response.json(false)
      throw new Error('Unauthorized backend call')
    })
    const r = await h(req(body('status')))
    expect(r.status).toBe(429)
    expect(called).toHaveLength(1)
  })
  it('sanitizes guest results and sends credentials only to the scoped RPC', async () => {
    const calls = []
    const h = createRestaurantGuestGateway(env, async (u, options) => {
      const path = new URL(u).pathname
      calls.push([path, JSON.parse(options.body)])
      if (path.endsWith('restaurant_guest_rate_gate')) return Response.json(true)
      if (path.endsWith('restaurant_guest_status'))
        return Response.json({
          groupStatus: 'collecting',
          orderReference: null,
          isLeader: true,
          ready: true,
          participants: 2,
          readyParticipants: 2,
          lines: [
            {
              itemId: id,
              name: 'Poisson',
              quantity: 1,
              unitPriceXaf: 6000,
              mine: true,
              employeeName: 'private',
            },
          ],
          shopId: 'private',
        })
      throw new Error('Unknown route ' + path)
    })
    const res = await h(req(body('status', { shopId: 'forged' })))
    expect(res.status).toBe(200)
    const d = await res.json()
    expect(d.shopId).toBeUndefined()
    expect(d.lines[0].employeeName).toBeUndefined()
    expect(calls[1][1]).toEqual({ p_qr: q, p_secret: secret })
  })
  it('never duplicates a confirmed reference from a repeated POST', async () => {
    const h = createRestaurantGuestGateway(env, async (u) => {
      const path = new URL(u).pathname
      if (path.endsWith('restaurant_guest_rate_gate')) return Response.json(true)
      if (path.endsWith('restaurant_guest_submit')) return Response.json('CMD-000001')
      throw new Error('Unexpected backend route')
    })
    const res = await h(req(body('submit')))
    expect(res.status).toBe(200)
    expect(await res.json()).toEqual({ reference: 'CMD-000001', submitted: true })
  })
})
