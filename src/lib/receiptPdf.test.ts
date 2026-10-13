import { describe, expect, it } from 'vitest'
import { makeConfirmedReceiptPdf } from './receiptPdf'

const paid = {
  shopName: 'YARO BOUTIQUE',
  receiptNumber: 'CV-2026-000001',
  confirmedAt: '2026-10-13T12:00:00.000Z',
  cashierFirstName: 'Marie-Lou',
  method: 'cash' as const,
  amountXaf: 7000,
  lines: [{ label: 'Robes', quantity: 2, lineTotalXaf: 7000 }],
}

describe('saved server-confirmed receipt PDF', () => {
  it('builds a self-contained downloadable PDF with a stable receipt number', async () => {
    const blob = makeConfirmedReceiptPdf(paid)
    expect(blob.type).toBe('application/pdf')
    const pdf = await blob.text()
    expect(pdf.startsWith('%PDF-1.4')).toBe(true)
    expect(pdf).toContain('xref\n')
    expect(pdf).toContain('startxref\n')
    expect(pdf).toContain('CV-2026-000001')
    expect(pdf).toContain('YARO BOUTIQUE')
    expect(pdf).toContain('/BaseFont /Helvetica')
    expect(pdf.trimEnd().endsWith('%%EOF')).toBe(true)
  })

  it('refuses tampered or incoherent payment records', () => {
    expect(() => makeConfirmedReceiptPdf({ ...paid, amountXaf: 8000 })).toThrow(/incohérent/)
    expect(() => makeConfirmedReceiptPdf({ ...paid, receiptNumber: ' ' })).toThrow(/incomplet/)
  })

  it('supports more than one page without overwriting receipt lines', async () => {
    const lines = Array.from({ length: 56 }, (_, index) => ({
      label: 'Chemise numéro ' + index,
      quantity: 1,
      lineTotalXaf: 100,
    }))
    const pdf = await makeConfirmedReceiptPdf({
      ...paid,
      amountXaf: 5600,
      lines,
    }).text()
    expect(pdf).toContain('/Count 2')
    expect(pdf).toContain('Chemise num')
    expect(pdf).toContain('5600')
  })
})
