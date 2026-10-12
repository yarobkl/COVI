import { describe, expect, it } from 'vitest'
import { parseCategorySaleHistory } from './categorySaleHistory'

const saved = {
  sale_id: '11111111-1111-4111-8111-111111111111',
  receipt_number: 'CV-2026-000012',
  confirmed_at: '2026-10-12T10:30:00Z',
  cashier_first_name: 'Awa',
  method: 'mobile_money',
  amount_xaf: 7800,
  receipt_lines: [
    { label: 'Robes', quantity: 2, lineTotalXaf: 7000 },
    { label: 'Ceintures', quantity: 1, lineTotalXaf: 800 },
  ],
}

describe('category sale history reconciliation', () => {
  it('reads category-only receipt lines and validates their financial sum', () => {
    expect(parseCategorySaleHistory([saved])).toEqual([
      {
        saleId: saved.sale_id,
        receiptNumber: saved.receipt_number,
        confirmedAt: saved.confirmed_at,
        cashierFirstName: 'Awa',
        method: 'mobile_money',
        amountXaf: 7800,
        isTest: false,
        lines: saved.receipt_lines,
      },
    ])
  })

  it('distinguishes TEST from actual receipts', () => {
    const result = parseCategorySaleHistory([
      { ...saved, receipt_number: 'CV-TEST-2026-000012' },
    ])
    expect(result[0].isTest).toBe(true)
  })

  it('rejects tampered totals, invalid quantities and duplicate sale IDs', () => {
    expect(() => parseCategorySaleHistory([{ ...saved, amount_xaf: 1 }])).toThrow()
    expect(() =>
      parseCategorySaleHistory([
        {
          ...saved,
          receipt_lines: [{ label: 'Robes', quantity: -1, lineTotalXaf: 7800 }],
        },
      ]),
    ).toThrow()
    expect(() => parseCategorySaleHistory([saved, saved])).toThrow()
  })
})
