import { afterEach, describe, expect, it, vi } from 'vitest'
import { receiptPdfFileName, shareReceiptPdf } from './receiptShare'

const paid = {
  shopName: 'YARO BOUTIQUE',
  receiptNumber: 'CV-2026-000125',
  confirmedAt: '2026-10-17T08:15:00.000Z',
  cashierFirstName: 'Marie-Lou',
  method: 'mobile_money',
  amountXaf: 3500,
  lines: [{ label: 'Robe', quantity: 1, lineTotalXaf: 3500 }],
}

afterEach(() => vi.unstubAllGlobals())

describe('native PDF invoice sharing', () => {
  it('provides a safe PDF filename from the recorded receipt reference', () => {
    expect(receiptPdfFileName('COVI/123 (A)')).toBe('COVI-facture-COVI-123-A-.pdf')
  })

  it('uses the iPhone share sheet with an actual PDF File when available', async () => {
    const share = vi.fn().mockResolvedValue(undefined)
    const canShare = vi.fn().mockReturnValue(true)
    vi.stubGlobal('navigator', { share, canShare })
    const result = await shareReceiptPdf(paid)
    expect(result).toBe('shared')
    const payload = share.mock.calls[0][0] as ShareData
    expect(payload.title).toBe('Facture COVI')
    expect(payload.files).toHaveLength(1)
    expect(payload.files?.[0].name).toBe('COVI-facture-CV-2026-000125.pdf')
    expect(payload.files?.[0].type).toBe('application/pdf')
    expect(payload.files?.[0].size).toBeGreaterThan(300)
    expect(canShare).toHaveBeenCalledOnce()
  })

  it('does not download if the user cancels sharing on iOS', async () => {
    const share = vi.fn().mockRejectedValue(new DOMException('Cancelled', 'AbortError'))
    vi.stubGlobal('navigator', { share, canShare: () => true })
    const result = await shareReceiptPdf(paid)
    expect(result).toBe('cancelled')
    expect(share).toHaveBeenCalledOnce()
  })

  it('falls back to downloading a real PDF if Web Share files are unsupported', async () => {
    const click = vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {})
    const create = vi.fn().mockReturnValue('blob:covi-test')
    const original = URL.createObjectURL
    URL.createObjectURL = create
    vi.stubGlobal('navigator', { canShare: () => false, share: vi.fn() })

    try {
      expect(await shareReceiptPdf(paid)).toBe('downloaded')
      expect(create).toHaveBeenCalledOnce()
      expect(click).toHaveBeenCalledOnce()
    } finally {
      URL.createObjectURL = original
      click.mockRestore()
    }
  })
})
