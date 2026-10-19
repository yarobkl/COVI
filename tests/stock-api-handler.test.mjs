// @vitest-environment node
import { describe, expect, it, vi } from 'vitest'
import { createStockApiHandler } from '../supabase/functions/stock-api/handler.mjs'

const env = {
  SUPABASE_URL: 'https://covi-test.supabase.co',
  SUPABASE_ANON_KEY: 'publishable-test-key',
  COVI_STOCK_API_ORIGINS: 'https://covi-snowy.vercel.app'
}
const shopId = '11111111-1111-4111-8111-111111111111'
const anotherShop = '22222222-2222-4222-8222-222222222222'
const ownerId = '33333333-3333-4333-8333-333333333333'
const productId = '44444444-4444-4444-8444-444444444444'
const url = 'https://covi-test.supabase.co/functions/v1/stock-api'
const headers = { authorization: 'Bearer user-jwt', origin: 'https://covi-snowy.vercel.app' }

function mockBackend({ owned = true, failedRpc = null } = {}) {
  const calls = []
  const transport = vi.fn(async (source, init) => {
    const target = new URL(String(source))
    calls.push({ target, init })
    if (target.pathname === '/auth/v1/user') return Response.json({ id: ownerId })
    if (target.pathname === '/rest/v1/shops') return Response.json(owned ? [{ id: shopId }] : [])
    if (target.pathname === '/rest/v1/products') {
      return Response.json([{ id: productId, shop_id: shopId, quantity_on_hand: 5, status: 'active' }])
    }
    if (target.pathname.endsWith('/adjust_product_stock_if_unchanged')) {
      if (failedRpc) return Response.json({ message: failedRpc }, { status: 400 })
      return Response.json({ id: productId, quantity_on_hand: 8, status: 'active' })
    }
    return Response.json({ message: 'unexpected' }, { status: 500 })
  })
  return { transport, calls }
}
function post(body) {
  return new Request(url + '/adjust', { method: 'POST',
    headers: { ...headers, 'content-type': 'application/json' }, body: JSON.stringify(body) })
}
const adjustment = {
  product_id: productId, expected_quantity: 5, quantity: 8,
  reason: 'restock', note: 'Reassort'
}

describe('API Stock — isolation, atomicite et validation', () => {
  it('refuse sans session et sans requete backend', async () => {
    const { transport } = mockBackend()
    const response = await createStockApiHandler(env, transport)(new Request(url))
    expect(response.status).toBe(401)
    expect(transport).not.toHaveBeenCalled()
  })
  it('refuse une origine inconnue', async () => {
    const { transport } = mockBackend()
    const response = await createStockApiHandler(env, transport)(
      new Request(url, { headers: { ...headers, origin: 'https://attacker.example' } }))
    expect(response.status).toBe(403)
    expect(transport).not.toHaveBeenCalled()
  })
  it('renvoie un prevol CORS uniquement pour l origine autorisee', async () => {
    const { transport } = mockBackend()
    const response = await createStockApiHandler(env, transport)(
      new Request(url, { method: 'OPTIONS', headers }))
    expect(response.status).toBe(204)
    expect(response.headers.get('access-control-allow-origin')).toBe(headers.origin)
    expect(transport).not.toHaveBeenCalled()
  })
  it('exige la propriete de la boutique avant toute liste', async () => {
    const { transport, calls } = mockBackend({ owned: false })
    const response = await createStockApiHandler(env, transport)(
      new Request(url + '?shop_id=' + anotherShop, { headers }))
    expect(response.status).toBe(404)
    expect(calls.some((call) => call.target.pathname === '/rest/v1/products')).toBe(false)
  })
  it('liste les articles sous le JWT du proprietaire avec pagination', async () => {
    const { transport, calls } = mockBackend()
    const response = await createStockApiHandler(env, transport)(
      new Request(url + '?shop_id=' + shopId + '&status=active&limit=1&offset=10', { headers }))
    expect(response.status).toBe(200)
    expect(await response.json()).toMatchObject({ shop_id: shopId, next_offset: 11,
      products: [{ quantity_on_hand: 5 }] })
    const read = calls.find((call) => call.target.pathname === '/rest/v1/products')
    expect(read.target.searchParams.get('shop_id')).toBe('eq.' + shopId)
    expect(read.target.searchParams.get('status')).toBe('eq.active')
    expect(read.init.headers.authorization).toBe(headers.authorization)
    expect(read.init.headers.apikey).toBe(env.SUPABASE_ANON_KEY)
    expect(JSON.stringify(calls)).not.toContain('service_role')
  })
  it('bloque les quantites invalides et les motifs inventes', async () => {
    const { transport, calls } = mockBackend()
    for (const altered of [{ quantity: -1 }, { quantity: 1.5 },
      { expected_quantity: null }, { reason: 'sale' }, { note: 'x'.repeat(201) }]) {
      const response = await createStockApiHandler(env, transport)(
        post({ ...adjustment, ...altered }))
      expect(response.status).toBe(400)
    }
    expect(calls.every((call) => !call.target.pathname.includes('/rpc/'))).toBe(true)
  })
  it('retourne 409 si un autre appareil a modifie le stock', async () => {
    const { transport } = mockBackend({ failedRpc: 'STOCK_CONFLICT' })
    const response = await createStockApiHandler(env, transport)(post(adjustment))
    expect(response.status).toBe(409)
    expect((await response.json()).error).toBe('stock_conflict')
  })
  it('utilise exclusivement la RPC auditee pour ecrire', async () => {
    const { transport, calls } = mockBackend()
    const response = await createStockApiHandler(env, transport)(post(adjustment))
    expect(response.status).toBe(200)
    expect((await response.json()).product.quantity_on_hand).toBe(8)
    const write = calls.find((call) => call.target.pathname.includes('/rpc/'))
    expect(write.init.method).toBe('POST')
    expect(JSON.parse(write.init.body)).toEqual({
      p_product_id: productId, p_expected_quantity: 5,
      p_quantity: 8, p_reason: 'restock', p_note: 'Reassort'
    })
  })
  it('n autorise aucune suppression ou modification directe par HTTP', async () => {
    const { transport } = mockBackend()
    const response = await createStockApiHandler(env, transport)(
      new Request(url, { method: 'DELETE', headers }))
    expect(response.status).toBe(405)
    expect(transport).not.toHaveBeenCalled()
  })
})
