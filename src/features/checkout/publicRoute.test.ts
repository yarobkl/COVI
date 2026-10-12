import { describe, expect, it } from 'vitest'
import { parseGuestOrderHash } from './publicRoute'

describe('feature-gated public link routing', () => {
  const token = 'dddddddd-0000-4000-8000-000000000001'

  it('routes QR and social links without requiring a client login', () => {
    expect(parseGuestOrderHash('#/commander/' + token + '?via=qr')).toEqual({
      token,
      channel: 'qr',
    })
    expect(parseGuestOrderHash('#/commander/' + token + '?via=social')).toEqual({
      token,
      channel: 'social',
    })
    expect(parseGuestOrderHash('#/commander/' + token)).toEqual({ token, channel: 'qr' })
  })

  it('does not hijack OAuth callback hashes or open unrelated pages', () => {
    for (const hash of [
      '#/caisse',
      '#access_token=secret',
      '#/commander/not-a-real-token',
      '#/commander/' + token + '?via=admin',
      '#/commander/' + token + '/pay',
    ]) {
      expect(parseGuestOrderHash(hash)).toBeNull()
    }
  })
})
