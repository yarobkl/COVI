import { describe, expect, it } from 'vitest'
import { orderLink, parsePublicHash, resolvePublicGatewayUrl, trackingLink } from './publicOrders'

const token = '0f8fad5b-d9cb-469f-a165-70867728950e'

describe('adresses publiques du canal client', () => {
  it('reconnaît le lien de commande et son canal', () => {
    expect(parsePublicHash(`#/commander/${token}?via=social`)).toEqual({
      kind: 'order',
      token,
      channel: 'social',
    })
    expect(parsePublicHash(`#/commander/${token.toUpperCase()}`)).toEqual({
      kind: 'order',
      token,
      channel: 'qr',
    })
  })

  it('reconnaît le lien de suivi', () => {
    expect(parsePublicHash(`#/suivi/${token}`)).toEqual({ kind: 'tracking', trackingToken: token })
  })

  it('laisse l’application de la boutique pour toute autre adresse', () => {
    expect(parsePublicHash('#/vendre')).toBeNull()
    expect(parsePublicHash('#/commander/pas-un-jeton')).toBeNull()
    expect(parsePublicHash(`#/commander/${token}/../vendre`)).toBeNull()
  })

  it('construit des liens qui se relisent', () => {
    const link = orderLink('https://covi-snowy.vercel.app', token, 'qr')
    expect(link).toBe(`https://covi-snowy.vercel.app/#/commander/${token}?via=qr`)
    expect(parsePublicHash(new URL(link).hash)).toMatchObject({ kind: 'order', channel: 'qr' })
    expect(parsePublicHash(new URL(trackingLink('https://x.example', token)).hash)).toMatchObject({
      kind: 'tracking',
    })
  })
})

describe('passerelle QR/social explicite, sans repli de production', () => {
  it('refuse une prévisualisation sans configuration, au lieu d’utiliser Supabase en production', () => {
    expect(resolvePublicGatewayUrl(undefined, undefined)).toBe('')
    expect(resolvePublicGatewayUrl('', '')).toBe('')
    expect(resolvePublicGatewayUrl('', 'not-a-url')).toBe('')
  })

  it('accepte uniquement une passerelle sécurisée, dans un chemin de fonction connu', () => {
    expect(resolvePublicGatewayUrl(undefined, 'https://covi-test.supabase.co/')).toBe(
      'https://covi-test.supabase.co/functions/v1/public-checkout',
    )
    expect(
      resolvePublicGatewayUrl(
        'https://covi-test.supabase.co/functions/v1/public-checkout',
        undefined,
      ),
    ).toBe('https://covi-test.supabase.co/functions/v1/public-checkout')
    expect(
      resolvePublicGatewayUrl('http://localhost:54321/functions/v1/public-checkout', undefined),
    ).toBe('http://localhost:54321/functions/v1/public-checkout')
  })

  it('bloque les URL frauduleuses, identifiants intégrés et redirections implicites', () => {
    for (const url of [
      'http://covi-test.supabase.co/functions/v1/public-checkout',
      'https://user:secret@covi-test.supabase.co/functions/v1/public-checkout',
      'https://covi-test.supabase.co/functions/v1/autre',
      'https://covi-test.supabase.co/functions/v1/public-checkout?private=1',
      'https://covi-test.supabase.co/functions/v1/public-checkout#secret',
    ]) {
      expect(resolvePublicGatewayUrl(url, 'https://covi-test.supabase.co')).toBe('')
    }
  })
})
