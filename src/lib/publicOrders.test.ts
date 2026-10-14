import { describe, expect, it } from 'vitest'
import { orderLink, parsePublicHash, trackingLink } from './publicOrders'

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
