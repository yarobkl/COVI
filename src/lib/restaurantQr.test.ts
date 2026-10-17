import { describe, expect, it } from 'vitest'
import { parseRestaurantQrHash, restaurantQrLink } from './restaurantQr'

describe('QR permanent Restaurant', () => {
  const token = 'b'.repeat(64)
  it('identifie uniquement le lien de table, sans shopId ou session personnelle', () => {
    expect(parseRestaurantQrHash(`#/table/${token}`)).toEqual({ kind: 'restaurantTable', token })
    expect(restaurantQrLink('https://covi.example', token)).toBe(
      `https://covi.example/#/table/${token}`,
    )
  })
  it('refuse les liens manipulés ou incomplets', () => {
    expect(parseRestaurantQrHash('#/table/04')).toBeNull()
    expect(parseRestaurantQrHash(`#/table/${token}/wrong`)).toBeNull()
    expect(parseRestaurantQrHash(`#/table/${token}?shop=other`)).toBeNull()
  })
})
