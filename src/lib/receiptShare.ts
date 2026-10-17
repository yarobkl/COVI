import { makeConfirmedReceiptPdf, type PdfReceiptData } from './receiptPdf'

/**
 * Share the *saved* receipt as a real PDF file through iOS/Android share sheets.
 * No uploads, payment-gateway calls, or third-party PDF services.
 */
export type PdfShareResult = 'shared' | 'downloaded' | 'cancelled'

export function receiptPdfFileName(reference: string): string {
  const safe = reference.replace(/[^a-zA-Z0-9_-]+/g, '-').slice(0, 70) || 'vente'
  return 'COVI-facture-' + safe + '.pdf'
}

function downloadPdf(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob)
  const element = document.createElement('a')
  element.href = url
  element.download = filename
  element.style.display = 'none'
  document.body.appendChild(element)
  try {
    element.click()
  } finally {
    element.remove()
    // Safari can still be reading the Blob when the click handler returns.
    window.setTimeout(() => URL.revokeObjectURL(url), 60_000)
  }
}

export function downloadReceiptPdf(receipt: PdfReceiptData): void {
  downloadPdf(makeConfirmedReceiptPdf(receipt), receiptPdfFileName(receipt.receiptNumber))
}

/** Must be called directly by a user click, before the iOS gesture expires. */
export async function shareReceiptPdf(receipt: PdfReceiptData): Promise<PdfShareResult> {
  const pdf = makeConfirmedReceiptPdf(receipt)
  const filename = receiptPdfFileName(receipt.receiptNumber)
  const file = new File([pdf], filename, { type: 'application/pdf' })

  let supported: boolean
  try {
    supported =
      typeof navigator.share === 'function' &&
      (typeof navigator.canShare !== 'function' || navigator.canShare({ files: [file] }))
  } catch {
    supported = false
  }

  if (supported) {
    try {
      // Call share() immediately. Do not wait for a network request beforehand:
      // iOS Safari requires the original user activation.
      await navigator.share({ title: 'Facture COVI', files: [file] })
      return 'shared'
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return 'cancelled'
      // Unexpected Web Share failures fall back to a file download.
    }
  }

  downloadPdf(pdf, filename)
  return 'downloaded'
}
