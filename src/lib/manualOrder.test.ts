import { beforeEach, describe, expect, it, vi } from 'vitest'
import { supabase } from './supabase'
import {
  approveManualCheckoutOrder,
  createManualCheckoutOrder,
  parseRecordedManualOrder,
  prepareManualOrderLines,
  prepareManualOrderRequest,
} from './manualOrder'

vi.mock('./supabase', () => ({
  supabase: { rpc: vi.fn() },
}))

const shopId = 'a8db9f0f-7207-4091-a194-48cb35c54b85'
const operationId = '703ce44a-3a18-4dc1-baa3-b70e566413e2'
const categoryId = '70c5aca9-8ebc-4dd6-9b6e-48a89db22a9a'
const otherCategoryId = '47463191-c122-4e44-a943-af45017cbf45'
const orderId = 'b0984ff1-497f-450f-8807-7e8f2329772c'

const request = {
  shopId,
  operationId,
  isTest: false,
  fulfillment: 'pickup' as const,
  customerPhone: ' +242 06 123 45 67 ',
  lines: [
    { categoryId, quantity: 2, negotiatedUnitPriceXaf: 3500 },
    { categoryId, quantity: 3, negotiatedUnitPriceXaf: 3500 },
    { categoryId: otherCategoryId, quantity: 1, negotiatedUnitPriceXaf: 5000 },
  ],
}

beforeEach(() => {
  vi.mocked(supabase.rpc).mockReset()
})

describe('manual checkout creation', () => {
  it('combines equal category/price lines without inventing per-item purchase costs', () => {
    const prepared = prepareManualOrderLines(request.lines)
    expect(prepared.lines).toHaveLength(2)
    expect(prepared.lines.find((line) => line.categoryId === categoryId)).toEqual({
      categoryId,
      quantity: 5,
      unitPriceXaf: 3500,
    })
    expect(prepared.amountXaf).toBe(22500)
    expect(request.lines[0].quantity).toBe(2)
  })

  it('preserves separate negotiated selling prices for the same category', () => {
    const prepared = prepareManualOrderLines([
      { categoryId, quantity: 1, negotiatedUnitPriceXaf: 2000 },
      { categoryId, quantity: 2, negotiatedUnitPriceXaf: 3000 },
    ])
    expect(prepared.lines).toHaveLength(2)
    expect(prepared.amountXaf).toBe(8000)
  })

  it('normalizes the phone without requiring it for in-person pickup', () => {
    expect(prepareManualOrderRequest(request).p_customer_phone).toBe('+242 06 123 45 67')
    expect(
      prepareManualOrderRequest({ ...request, customerPhone: undefined }).p_customer_phone,
    ).toBeNull()
  })

  it('rejects malformed categories, amounts and combined quantity overflow', () => {
    expect(() => prepareManualOrderLines([])).toThrow()
    expect(() =>
      prepareManualOrderLines([{ categoryId: 'bad', quantity: 1, negotiatedUnitPriceXaf: 100 }]),
    ).toThrow()
    for (const price of [-1, 12.5, Infinity, NaN]) {
      expect(() =>
        prepareManualOrderLines([{ categoryId, quantity: 1, negotiatedUnitPriceXaf: price }]),
      ).toThrow()
    }
    expect(() =>
      prepareManualOrderLines([
        { categoryId, quantity: 2147483647, negotiatedUnitPriceXaf: 0 },
        { categoryId, quantity: 1, negotiatedUnitPriceXaf: 0 },
      ]),
    ).toThrow()
    expect(() =>
      prepareManualOrderLines([
        { categoryId, quantity: 10, negotiatedUnitPriceXaf: 9_000_000_000_000 },
      ]),
    ).toThrow()
  })

  it('uses RPC instead of writing orders or stock directly', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { orderId, status: 'submitted', amountXaf: 22500 },
      error: null,
    } as never)
    const result = await createManualCheckoutOrder(request)
    expect(result).toEqual({ orderId, status: 'submitted', amountXaf: 22500 })
    expect(supabase.rpc).toHaveBeenCalledWith('create_manual_checkout_order', {
      p_shop_id: shopId,
      p_operation_id: operationId,
      p_is_test: false,
      p_customer_phone: '+242 06 123 45 67',
      p_customer_note: null,
      p_fulfillment: 'pickup',
      p_lines: prepareManualOrderLines(request.lines).lines,
    })
  })

  it('approves through the dedicated owner-authorized RPC', async () => {
    vi.mocked(supabase.rpc).mockResolvedValueOnce({
      data: { orderId, status: 'approved', amountXaf: 22500 },
      error: null,
    } as never)
    await expect(approveManualCheckoutOrder({ shopId, orderId })).resolves.toEqual({
      orderId,
      status: 'approved',
      amountXaf: 22500,
    })
    expect(supabase.rpc).toHaveBeenCalledWith('approve_manual_checkout_order', {
      p_shop_id: shopId,
      p_order_id: orderId,
    })
  })

  it('rejects server responses that are incomplete or unapproved', () => {
    expect(() => parseRecordedManualOrder(null)).toThrow()
    expect(() =>
      parseRecordedManualOrder({ orderId: 'bad', status: 'approved', amountXaf: 20 }),
    ).toThrow()
    expect(() =>
      parseRecordedManualOrder({ orderId, status: 'auto_paid', amountXaf: 20 }),
    ).toThrow()
  })
})
