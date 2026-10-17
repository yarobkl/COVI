import { beforeEach, describe, expect, it, vi } from 'vitest'
import { supabase } from './supabase'
import { listCheckoutStockCategories, parseCheckoutStockCategories } from './checkoutCategoryStock'

vi.mock('./supabase', () => ({
  supabase: { from: vi.fn() },
}))

const shopId = '11111111-1111-4111-8111-111111111111'
const robeId = 'aaaaaaaa-0000-4000-8000-000000000001'

const row = {
  id: robeId,
  shop_id: shopId,
  display_name: ' Robes ',
  quantity_on_hand: 7,
  quantity_reserved: 2,
  is_test: false,
}

beforeEach(() => {
  vi.mocked(supabase.from).mockReset()
})

describe('future COVI category-only stock reader', () => {
  it('subtracts reserved units and keeps scope within the requested shop', () => {
    expect(parseCheckoutStockCategories([row], shopId, false)).toEqual([
      { id: robeId, shopId, label: 'Robes', available: 5, isTest: false },
    ])
  })

  it('rejects mixed demo and real inventory, other shops and invalid stock', () => {
    for (const malformed of [
      { ...row, is_test: true },
      { ...row, shop_id: '22222222-2222-4222-8222-222222222222' },
      { ...row, quantity_on_hand: 1, quantity_reserved: 3 },
      { ...row, quantity_on_hand: 0.5 },
    ]) {
      expect(() => parseCheckoutStockCategories([malformed], shopId, false)).toThrow()
    }
    expect(() => parseCheckoutStockCategories([row, row], shopId, false)).toThrow()
  })

  it('queries the new category stock only, never legacy products', async () => {
    const order = vi.fn().mockResolvedValue({ data: [row], error: null })
    const eqTest = vi.fn().mockReturnValue({ order })
    const eqShop = vi.fn().mockReturnValue({ eq: eqTest })
    const select = vi.fn().mockReturnValue({ eq: eqShop })
    vi.mocked(supabase.from).mockReturnValue({ select } as never)

    const result = await listCheckoutStockCategories(shopId, false)
    expect(result[0].available).toBe(5)
    expect(supabase.from).toHaveBeenCalledWith('stock_categories')
    expect(eqShop).toHaveBeenCalledWith('shop_id', shopId)
    expect(eqTest).toHaveBeenCalledWith('is_test', false)
    expect(order).toHaveBeenCalledWith('display_name', { ascending: true })
  })
})
