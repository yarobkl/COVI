import qrcode from '../vendor/qrcode-generator.mjs'

/** A SCANNABLE QR, generated entirely in the customer's browser.
 * No access token, shop URL or customer data goes to a third-party QR server.
 * qrcode-generator is distributed locally with its MIT license.
 */
export function localQrSvgDataUrl(value: string): string {
  if (typeof value !== 'string' || value.length < 1 || value.length > 1024)
    throw new Error('Lien du QR code invalide.')
  const url = new URL(value)
  if (url.protocol !== 'https:' && url.hostname !== 'localhost')
    throw new Error('Le QR code doit pointer vers un lien sécurisé.')

  // Automatically selects the correct QR version for URL length.
  const qr = qrcode(0, 'M')
  qr.addData(value)
  qr.make()
  const svg = qr.createSvgTag({ cellSize: 6, margin: 24, scalable: true })
  // SVG is shape-only and created by the bundled library, never user HTML.
  return 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg)
}
