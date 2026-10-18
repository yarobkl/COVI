import { describe, expect, it } from 'vitest'
import { parseRecordedCheckoutReceipt } from './manualCheckout'

const valid = {
  saleId: '39d93595-62e6-4e42-b9ae-581dc5cd367e',
  receiptNumber: 'CV-2026-000125',
  confirmedAt: '2026-10-12T12:10:00Z',
  cashierFirstName: 'Marie Lou',
  method: 'mobile_money',
  amountXaf: 12500,
  lines: [
    { label: 'Robes', quantity: 2, lineTotalXaf: 7000 },
    { label: 'Chemises', quantity: 1, lineTotalXaf: 5500 },
  ],
}

describe('server-confirmed checkout receipt parsing', () => {
  it('uses the persisted receipt and cashier identity returned by the server', () => {
    expect(parseRecordedCheckoutReceipt(valid)).toEqual(valid)
  })

  it('rejects any receipt whose sum differs from the saved total', () => {
    expect(() =>
      parseRecordedCheckoutReceipt({
        ...valid,
        amountXaf: 15000,
      }),
    ).toThrow('incohérent')
  })

  it('rejects malformed server replies rather than displaying a fake paid receipt', () => {
    for (const reply of [
      null,
      {},
      { ...valid, receiptNumber: '' },
      { ...valid, cashierFirstName: '' },
      { ...valid, confirmedAt: 'invalid' },
      { ...valid, method: 'automatic_gateway' },
      { ...valid, lines: [] },
      { ...valid, lines: [{ label: 'Robes', quantity: -1, lineTotalXaf: 12500 }] },
      { ...valid, lines: [{ label: 'Robes', quantity: 2, lineTotalXaf: NaN }] },
    ]) {
      expect(() => parseRecordedCheckoutReceipt(reply)).toThrow()
    }
  })

  it('does not mix real and test receipt labels when parsing', () => {
    const testReceipt = { ...valid, receiptNumber: 'CV-TEST-2026-000001' }
    expect(parseRecordedCheckoutReceipt(testReceipt).receiptNumber).toBe('CV-TEST-2026-000001')
  })
})
