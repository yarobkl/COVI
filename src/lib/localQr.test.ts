import { describe, expect, it } from 'vitest'
import { localQrSvgDataUrl } from './localQr'

describe('locally encoded scannable QR for permanent COVI shop links', () => {
  it('embeds a real vector QR locally without sending the token to an external image API', () => {
    const url = 'https://covi.example/#/commander/dddddddd-0000-4000-8000-000000000001?via=qr'
    const result = localQrSvgDataUrl(url)
    expect(result).toMatch(/^data:image\/svg\+xml;charset=utf-8,/)
    const svg = decodeURIComponent(result.slice(result.indexOf(',') + 1))
    expect(svg).toContain('<svg')
    expect(svg).toContain('</svg>')
    expect(svg).toContain('<rect')
  })

  it('rejects malformed or insecure URLs', () => {
    expect(() => localQrSvgDataUrl('')).toThrow()
    expect(() => localQrSvgDataUrl('http://covi.example/#/commander/abc')).toThrow()
    expect(() => localQrSvgDataUrl('javascript:alert(1)')).toThrow()
  })
})
