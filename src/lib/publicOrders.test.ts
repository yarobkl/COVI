import { beforeEach, describe, expect, it, vi } from 'vitest'
import { supabase } from './supabase'
import {
  configurePublicOrderLink,
  getPublicCatalog,
  getPublicOrderLink,
  getPendingPublicOrders,
  parsePendingPublicOrders,
  preparePublicRequest,
  publicOrderUrl,
  rotatePublicOrderLink,
  submitPublicOrder,
} from './publicOrders'

vi.mock('./supabase', () => ({ supabase: { rpc: vi.fn() } }))
const token = 'dddddddd-0000-4000-8000-000000000001'
const shopId = '11111111-1111-4111-8111-111111111111'
const categoryId = 'aaaaaaaa-0000-4000-8000-000000000001'
const orderId = 'bbbbbbbb-0000-4000-8000-000000000001'
const operationId = '77770000-0000-4000-8000-000000000001'

beforeEach(() => vi.mocked(supabase.rpc).mockReset())

describe('public checkout links and restricted requests', () => {
  it('keeps owner link disabled by default and updates it only through owner RPC', async () => {
    vi.mocked(supabase.rpc)
      .mockResolvedValueOnce({ data: null, error: null } as never)
      .mockResolvedValueOnce({ data: { publicToken: token, enabled: true }, error: null } as never)
      .mockResolvedValueOnce({ data: { publicToken: token, enabled: true }, error: null } as never)
    await expect(getPublicOrderLink(shopId)).resolves.toBeNull()
    await expect(configurePublicOrderLink(shopId, true)).resolves.toEqual({
      publicToken: token, enabled: true,
    })
    expect(supabase.rpc).toHaveBeenCalledWith('configure_checkout_public_link', {
      p_shop_id: shopId, p_enabled: true,
    })
    await expect(rotatePublicOrderLink(shopId)).resolves.toEqual({
      publicToken: token, enabled: true,
    })
  })

  it('creates stable QR and social URLs without depending on a third-party QR service', () => {
    const base = 'https://covi.example/path?private=1#/caisse'
    expect(publicOrderUrl(base, token, 'qr'))
      .toBe('https://covi.example/path#/commander/' + token + '?via=qr')
    expect(publicOrderUrl(base, token, 'social')).toContain('?via=social')
    expect(() => publicOrderUrl('http://covi.example', token, 'qr')).toThrow('sécurisé')
  })

  it('exposes category labels only, not costs or stock counts', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { shopName: 'Boutique A', categories: [{ id: categoryId, label: 'Robes' }] },
      error: null,
    } as never)
    expect(await getPublicCatalog(token)).toEqual({
      shopName: 'Boutique A', categories: [{ id: categoryId, label: 'Robes' }],
    })
    expect(supabase.rpc).toHaveBeenCalledWith('get_checkout_public_catalog', { p_token: token })
  })

  it('requires positive negotiated prices and contact for delivery, with 20-piece limit', () => {
    const valid = {
      token, channel: 'social' as const, operationId,
      lines: [{ categoryId, quantity: 2, negotiatedUnitPriceXaf: 3500 }],
      fulfillment: 'pickup' as const,
    }
    expect(preparePublicRequest(valid).p_lines).toEqual([
      { categoryId, quantity: 2, unitPriceXaf: 3500 },
    ])
    expect(() => preparePublicRequest({ ...valid, fulfillment: 'delivery' })).toThrow()
    expect(() => preparePublicRequest({
      ...valid, lines: [{ categoryId, quantity: 1, negotiatedUnitPriceXaf: 0 }],
    })).toThrow()
    expect(() => preparePublicRequest({
      ...valid, lines: [{ categoryId, quantity: 21, negotiatedUnitPriceXaf: 3500 }],
    })).toThrow()
  })

  it('submits a request, never a payment, using server-side RPC', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { orderId, status: 'submitted', amountXaf: 7000 }, error: null,
    } as never)
    expect(await submitPublicOrder({
      token, channel: 'qr', operationId,
      lines: [{ categoryId, quantity: 2, negotiatedUnitPriceXaf: 3500 }],
      fulfillment: 'pickup',
    })).toEqual({ orderId, status: 'submitted', amountXaf: 7000 })
    expect(supabase.rpc).toHaveBeenCalledWith('submit_checkout_public_order',
      expect.objectContaining({
        p_channel: 'qr',
        p_token: token,
        p_operation_id: operationId,
      }))
  })

  it('refuses customer details leaked through invalid private inbox replies', () => {
    expect(() => parsePendingPublicOrders([{
      orderId, channel: 'social', status: 'submitted', amountXaf: 3500,
      createdAt: '2026-10-12T17:00:00Z', customerPhone: null,
      customerNote: null, fulfillment: 'delivery',
      lines: [{ label: 'Robes', quantity: 1, lineTotalXaf: 2000 }],
    }])).toThrow('incohérent')
  })

  it('queries customer contact data only from an owner-restricted function', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({ data: [], error: null } as never)
    expect(await getPendingPublicOrders(shopId)).toEqual([])
    expect(supabase.rpc).toHaveBeenCalledWith('get_checkout_pending_orders', {
      p_shop_id: shopId,
    })
  })
})
