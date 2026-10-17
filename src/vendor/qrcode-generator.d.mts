/** Minimal declarations for the unmodified MIT-licensed QR generator bundled locally. */
export interface QRCode {
  addData(value: string): void
  make(): void
  createSvgTag(options?: {
    cellSize?: number
    margin?: number
    scalable?: boolean
  }): string
}

declare const qrcode: (
  typeNumber: number,
  errorCorrectionLevel: 'L' | 'M' | 'Q' | 'H'
) => QRCode
export default qrcode
