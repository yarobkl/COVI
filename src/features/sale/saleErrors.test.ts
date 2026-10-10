import { describe, expect, it } from 'vitest'
import { saleErrorMessage } from './saleErrors'

const err = (message: string) => ({ message, code: 'P0001' })

describe('saleErrorMessage', () => {
  it('translates the server refusals', () => {
    expect(saleErrorMessage(err('Insufficient stock'), { remaining: 1 })).toBe(
      'Il n’en reste que 1. Baissez la quantité.',
    )
    expect(saleErrorMessage(err('Insufficient stock'))).toBe(
      'Il n’en reste pas assez. Baissez la quantité.',
    )
    expect(saleErrorMessage(err('Product unavailable'))).toBe(
      'Cet article n’est plus en stock. Il a peut-être déjà été vendu.',
    )
    expect(saleErrorMessage(err('Unique piece quantity must be 1'))).toBe(
      'C’est une pièce unique : la quantité est 1.',
    )
    expect(saleErrorMessage(err('Quantity must be positive'))).toBe('Indiquez au moins 1 pièce.')
    expect(saleErrorMessage(err('Sold price cannot be negative'))).toBe(
      'Indiquez le prix auquel vous avez vendu.',
    )
    expect(saleErrorMessage(err('Invalid payment method'))).toBe(
      'Choisissez comment la cliente a payé.',
    )
    expect(saleErrorMessage(err('Authentication required'))).toMatch(/^Votre session a pris fin/)
    expect(saleErrorMessage(err('Sale operation id is required'))).toBe(
      'Ça n’a pas marché. Validez la vente une nouvelle fois.',
    )
  })

  it('translates the offline queue messages', () => {
    expect(
      saleErrorMessage(
        new Error(
          'Produit absent du stock hors connexion. Reconnectez-vous pour actualiser le stock.',
        ),
      ),
    ).toMatch(/^Cet article n’est pas dans le stock gardé sur ce téléphone/)
    expect(
      saleErrorMessage(new Error('Stock hors connexion insuffisant pour cette vente.'), {
        remaining: 2,
      }),
    ).toBe('D’après ce téléphone, il n’en reste que 2. Baissez la quantité.')
    expect(
      saleErrorMessage(new Error('Session introuvable. Reconnectez-vous pour enregistrer.')),
    ).toMatch(/^Votre session a pris fin/)
  })

  it('never shows a technical message', () => {
    expect(saleErrorMessage(err('duplicate key value violates unique constraint'))).toBe(
      'Ça n’a pas marché. Vérifiez le réseau puis réessayez.',
    )
    expect(saleErrorMessage(null)).toBe('Ça n’a pas marché. Vérifiez le réseau puis réessayez.')
  })
})
