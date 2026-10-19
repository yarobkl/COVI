// @vitest-environment node
import { describe, expect, it, vi } from 'vitest'
import { createWebsiteConnectGateway } from '../supabase/functions/covi-connect/gateway.mjs'

const env = {
  SUPABASE_URL: 'https://covi-demo.supabase.co',
  SUPABASE_ANON_KEY: 'a-valid-test-publishable-key-for-mocks',
  SUPABASE_SERVICE_ROLE_KEY: 'a-valid-long-service-role-secret-for-mocks',
  COVI_SITE_MANAGEMENT_ORIGIN: 'https://covi-snowy.vercel.app',
}
const siteKey = 'covi_site_' + 'a'.repeat(64)
const connId = '11111111-1111-4111-8111-111111111111'
const shopId = '22222222-2222-4222-8222-222222222222'
const productId = '33333333-3333-4333-8333-333333333333'
const userId = '44444444-4444-4444-8444-444444444444'
const base = 'https://covi-demo.supabase.co/functions/v1/covi-connect'
const request = (path, method = 'GET', key = siteKey, body) =>
  new Request(base + path, {
    method,
    headers: { 'x-covi-key': key, ...(body ? { 'content-type': 'application/json' } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  })
const sampleOrder = {
  externalOrderId: 'WC-1025',
  customerName: 'Awa',
  customerPhone: '+242060000000',
  paymentMethod: 'mobile_money',
  fulfillment: 'pickup',
  lines: [{ productId, quantity: 2 }],
}
function backend({ active = true, limit = true, imported = true } = {}) {
  const calls = []
  const send = vi.fn(async (url, init) => {
    const u = new URL(String(url))
    calls.push({ path: u.pathname, search: u.searchParams, init })
    if (u.pathname === '/auth/v1/user') return Response.json({ id: userId })
    if (u.pathname.endsWith('/authorize_website_connection'))
      return Response.json(active ? { id: connId, shopId } : null)
    if (u.pathname.endsWith('/consume_website_api_quota')) return Response.json(limit)
    if (u.pathname === '/rest/v1/products')
      return Response.json([
        {
          id: productId,
          name: 'Pantalon',
          initial_sale_price: 10000,
          quantity_on_hand: 8,
          status: 'active',
          updated_at: '2026-10-19T12:00:00Z',
        },
      ])
    if (u.pathname.endsWith('/import_website_order'))
      return Response.json({
        orderId: '55555555-5555-4555-8555-555555555555',
        status: 'new',
        alreadyImported: !imported,
        amountXaf: 20000,
      })
    if (u.pathname.endsWith('/get_website_order_state'))
      return Response.json({ status: 'new', reference: 'C-ABC123' })
    if (u.pathname.endsWith('/list_website_connections')) return Response.json([])
    if (u.pathname.endsWith('/create_website_connection'))
      return Response.json({ id: connId, secret: siteKey })
    if (u.pathname.endsWith('/revoke_website_connection')) return Response.json(true)
    return Response.json({ message: 'unexpected' }, { status: 500 })
  })
  return { send, calls }
}
describe('COVI Connect v1', () => {
  it('rejects unknown keys before product access', async () => {
    const { send, calls } = backend({ active: false })
    const res = await createWebsiteConnectGateway(env, send)(request('/products'))
    expect(res.status).toBe(401)
    expect(calls.some((c) => c.path === '/rest/v1/products')).toBe(false)
  })
  it('rejects partner keys in a browser even with COVI origin', async () => {
    const { send } = backend()
    const res = await createWebsiteConnectGateway(
      env,
      send,
    )(
      new Request(base + '/products', {
        headers: { Origin: 'https://covi-snowy.vercel.app', 'x-covi-key': siteKey },
      }),
    )
    expect(res.status).toBe(403)
  })
  it('reads only the authorized shop without simulated products', async () => {
    const { send, calls } = backend()
    const res = await createWebsiteConnectGateway(env, send)(request('/products?limit=20&offset=0'))
    expect(res.status).toBe(200)
    expect((await res.json()).products[0]).toMatchObject({ name: 'Pantalon', quantity: 8 })
    const p = calls.find((c) => c.path === '/rest/v1/products')
    expect(p.search.get('shop_id')).toBe('eq.' + shopId)
    expect(p.search.get('is_test')).toBe('eq.false')
  })
  it('validates customer order and does not write direct sale or stock', async () => {
    const { send, calls } = backend()
    const res = await createWebsiteConnectGateway(
      env,
      send,
    )(request('/orders', 'POST', siteKey, sampleOrder))
    const body = await res.json()
    expect(res.status).toBe(200)
    expect(body.paymentConfirmed).toBe(false)
    expect(body.order.status).toBe('new')
    expect(calls.filter((c) => c.path.includes('/rpc/')).map((c) => c.path)).toContain(
      '/rest/v1/rpc/import_website_order',
    )
    expect(
      calls.some((c) => c.path.includes('record_sale') || c.path.includes('adjust_product_stock')),
    ).toBe(false)
    const imported = calls.find((c) => c.path.endsWith('/import_website_order'))
    expect(JSON.parse(imported.init.body).p_connection_id).toBe(connId)
    expect(JSON.parse(imported.init.body).p_lines).toEqual([{ productId, quantity: 2 }])
  })
  it('rejects malformed lines and arbitrary prices before import', async () => {
    const { send, calls } = backend()
    const wrong = { ...sampleOrder, lines: [{ productId, quantity: 2, unitPrice: 1 }] }
    const res = await createWebsiteConnectGateway(
      env,
      send,
    )(request('/orders', 'POST', siteKey, wrong))
    expect(res.status).toBe(400)
    expect(calls.some((c) => c.path.endsWith('import_website_order'))).toBe(false)
  })
  it('limits requests per connection', async () => {
    const { send } = backend({ limit: false })
    const res = await createWebsiteConnectGateway(env, send)(request('/products'))
    expect(res.status).toBe(429)
  })
  it('retrieves the website order state via connection-scoped RPC', async () => {
    const { send, calls } = backend()
    const res = await createWebsiteConnectGateway(env, send)(request('/orders?external_id=WC-1025'))
    expect(res.status).toBe(200)
    expect((await res.json()).order.status).toBe('new')
    const state = calls.find((c) => c.path.endsWith('get_website_order_state'))
    expect(JSON.parse(state.init.body).p_connection_id).toBe(connId)
  })
  it('requires owner session for connection management', async () => {
    const { send } = backend()
    const res = await createWebsiteConnectGateway(
      env,
      send,
    )(new Request(base + '/manage?shop_id=' + shopId))
    expect(res.status).toBe(401)
  })
  it('supports creating a key only through owner JWT + own RPC', async () => {
    const { send, calls } = backend()
    const res = await createWebsiteConnectGateway(
      env,
      send,
    )(
      new Request(base + '/manage', {
        method: 'POST',
        headers: {
          Origin: 'https://covi-snowy.vercel.app',
          Authorization: 'Bearer owner-jwt',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          action: 'create',
          shopId,
          label: 'Mon site',
          siteUrl: 'https://shop.example',
        }),
      }),
    )
    expect(res.status).toBe(200)
    expect((await res.json()).result.secret).toBe(siteKey)
    const call = calls.find((c) => c.path.endsWith('create_website_connection'))
    expect(call.init.headers.apikey).toBe(env.SUPABASE_ANON_KEY)
    expect(call.init.headers.authorization).toBe('Bearer owner-jwt')
  })
  it('does not accept cross-origin management calls', async () => {
    const { send } = backend()
    const res = await createWebsiteConnectGateway(
      env,
      send,
    )(new Request(base + '/manage', { headers: { Origin: 'https://evil.example' } }))
    expect(res.status).toBe(403)
    expect(send).not.toHaveBeenCalled()
  })
})
