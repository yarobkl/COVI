// @vitest-environment node
import { describe, expect, it, vi } from 'vitest'
import { createPublicCheckoutGateway } from '../supabase/functions/public-checkout/gateway.mjs'

const env = {
  COVI_GATEWAY_ENABLED: 'true',
  COVI_PUBLIC_ORIGIN: 'https://covi.example',
  SUPABASE_URL: 'https://example.supabase.co',
  COVI_SUPABASE_SECRET_KEY: 'sb_secret_test_backend_never_in_browser',
  COVI_GATEWAY_PEPPER: 'gateway-pepper-with-at-least-32-random-characters',
  COVI_TURNSTILE_SECRET: 'turnstile-secret-key-for-the-test-only',
}
const token = 'dddddddd-0000-4000-8000-000000000001'
const operationId = '77770000-0000-4000-8000-000000000001'
const categoryId = 'aaaaaaaa-0000-4000-8000-000000000001'
const orderId = 'bbbbbbbb-0000-4000-8000-000000000001'
const origin = { Origin: 'https://covi.example' }
const order = {
  token,
  channel: 'qr',
  operationId,
  fulfillment: 'pickup',
  lines: [{ categoryId, quantity: 2, unitPriceXaf: 3500 }],
  challenge: 'valid-turnstile-token-for-test',
}

function fakeBackend({ quota = true, captcha = true } = {}) {
  const calls = []
  const transport = vi.fn(async (url, init) => {
    const address = String(url)
    calls.push({ address, init })
    if (address.includes('siteverify')) {
      return Response.json({
        success: captcha,
        hostname: 'covi.example',
        action: 'covi_checkout',
      })
    }
    if (address.endsWith('consume_checkout_gateway_quota')) return Response.json(quota)
    if (address.endsWith('get_checkout_public_catalog')) {
      return Response.json({
        shopName: 'La boutique',
        categories: [{ id: categoryId, label: 'Robes' }],
      })
    }
    if (address.endsWith('submit_checkout_public_order')) {
      return Response.json({ orderId, status: 'submitted', amountXaf: 7000 })
    }
    throw new Error('Unexpected endpoint')
  })
  return { transport, calls }
}

function guestPost(input = order, extraHeaders = {}) {
  return new Request('https://example.supabase.co/functions/v1/public-checkout', {
    method: 'POST',
    headers: { ...origin, 'Content-Type': 'application/json', ...extraHeaders },
    body: JSON.stringify(input),
  })
}

describe('isolated QR/social gateway', () => {
  it('fails closed when disabled or missing secrets, and never accesses Supabase', async () => {
    const { transport } = fakeBackend()
    const disabled = createPublicCheckoutGateway({ ...env, COVI_GATEWAY_ENABLED: 'false' }, transport)
    expect((await disabled(guestPost())).status).toBe(503)
    const missing = createPublicCheckoutGateway({ ...env, COVI_TURNSTILE_SECRET: '' }, transport)
    expect((await missing(guestPost())).status).toBe(503)
    expect(transport).not.toHaveBeenCalled()
  })

  it('rejects foreign origins without reflecting permissive CORS', async () => {
    const { transport } = fakeBackend()
    const request = guestPost(order, { Origin: 'https://attacker.example' })
    const result = await createPublicCheckoutGateway(env, transport)(request)
    expect(result.status).toBe(403)
    expect(result.headers.get('access-control-allow-origin')).toBeNull()
    expect(transport).not.toHaveBeenCalled()
  })

  it('serves only public categories via two atomic quotas; no client secret', async () => {
    const { transport, calls } = fakeBackend()
    const request = new Request(
      'https://example.supabase.co/functions/v1/public-checkout?token=' + token,
      { headers: origin },
    )
    const result = await createPublicCheckoutGateway(env, transport)(request)
    expect(result.status).toBe(200)
    const catalog = await result.json()
    expect(catalog.categories).toEqual([{ id: categoryId, label: 'Robes' }])
    expect(result.headers.get('cache-control')).toBe('no-store')
    expect(calls.filter((call) => call.address.includes('gateway_quota'))).toHaveLength(2)
    expect(JSON.stringify(catalog)).not.toContain(env.COVI_SUPABASE_SECRET_KEY)
  })

  it('checks a single-use anti-robot challenge before saving an order', async () => {
    const { transport, calls } = fakeBackend()
    const result = await createPublicCheckoutGateway(env, transport)(guestPost())
    expect(result.status).toBe(200)
    expect(await result.json()).toEqual({
      orderId,
      status: 'submitted',
      amountXaf: 7000,
    })
    const rpc = calls.find((c) => c.address.includes('submit_checkout_public_order'))
    expect(rpc).toBeTruthy()
    const payload = JSON.parse(rpc.init.body)
    expect(payload.p_lines).toEqual(order.lines)
    expect(payload.p_channel).toBe('qr')
    expect(payload.p_customer_phone).toBeNull()
    expect(calls.filter((c) => c.address.includes('gateway_quota'))).toHaveLength(3)
    expect(calls.some((c) => c.address.includes('siteverify'))).toBe(true)
  })

  it('does not save when challenge failed or wrong hostname/action', async () => {
    const { transport, calls } = fakeBackend({ captcha: false })
    const result = await createPublicCheckoutGateway(env, transport)(guestPost())
    expect(result.status).toBe(403)
    expect(calls.some((c) => c.address.includes('submit_checkout_public_order'))).toBe(false)
  })

  it('stops source flooding before expensive external verification', async () => {
    const { transport, calls } = fakeBackend({ quota: false })
    const result = await createPublicCheckoutGateway(env, transport)(guestPost())
    expect(result.status).toBe(429)
    expect(calls.some((c) => c.address.includes('siteverify'))).toBe(false)
  })

  it('rejects price manipulation, bad quantities and delivery without phone', async () => {
    const { transport } = fakeBackend()
    const gateway = createPublicCheckoutGateway(env, transport)
    expect((await gateway(guestPost({ ...order, lines: [{ ...order.lines[0], quantity: 21 }] }))).status).toBe(400)
    expect((await gateway(guestPost({ ...order, lines: [{ ...order.lines[0], unitPriceXaf: -1 }] }))).status).toBe(400)
    expect((await gateway(guestPost({ ...order, fulfillment: 'delivery' }))).status).toBe(400)
    expect(transport).not.toHaveBeenCalled()
  })

  it('enforces JSON-only input and never accepts payment or staff actions', async () => {
    const { transport } = fakeBackend()
    const gateway = createPublicCheckoutGateway(env, transport)
    const bad = new Request('https://example.supabase.co/functions/v1/public-checkout', {
      method: 'POST',
      headers: { ...origin, 'Content-Type': 'text/plain' },
      body: 'anything',
    })
    expect((await gateway(bad)).status).toBe(415)
    const forged = { ...order, action: 'confirm_payment', status: 'paid' }
    const res = await gateway(guestPost(forged))
    expect(res.status).toBe(200)
    const calls = transport.mock.calls
    expect(calls.some(([url]) => String(url).includes('confirm_manual_checkout_payment'))).toBe(false)
  })
})
