import { describe, expect, it } from 'vitest'
import type { PendingSale, RejectedSale } from '../../lib/offline'
import { refusedSales, rejectionReason, waitingSales } from './offlineSales'

describe('rejectionReason', () => {
  it('says why the account refused a sale, in the shop’s words', () => {
    expect(rejectionReason('Product unavailable')).toBe(
      'Il n’était plus en stock : il a sans doute été vendu sur un autre appareil.',
    )
    expect(rejectionReason('Insufficient stock')).toMatch(/^Il n’en restait plus assez/)
    expect(rejectionReason('Unique piece quantity must be 1')).toMatch(/^C’est une pièce unique/)
    expect(rejectionReason('Quantity must be positive')).toBe(
      'La quantité notée n’était pas bonne.',
    )
    expect(rejectionReason('Sold price cannot be negative')).toBe('Le prix noté n’était pas bon.')
    expect(rejectionReason('Invalid payment method')).toBe(
      'Le moyen de paiement n’a pas été reconnu.',
    )
    expect(rejectionReason('Authentication required')).toBe(
      'Votre session avait pris fin au moment de l’envoi.',
    )
  })

  it('never shows a technical message', () => {
    for (const raw of ['duplicate key value violates unique constraint "x"', '', null, undefined])
      expect(rejectionReason(raw)).toBe('Le compte ne l’a pas acceptée.')
  })
})

const pending = (id: string, createdAt: string, extra: Partial<PendingSale> = {}): PendingSale => ({
  id,
  shopId: 'shop-1',
  productId: 'p-b',
  quantity: 1,
  soldUnitPrice: 22000,
  paymentLabel: 'Espèces',
  createdAt,
  attempts: 0,
  ...extra,
})

describe('sales kept on the device', () => {
  const names = new Map([['p-b', 'Jean droit modèle B']])

  it('shows refused sales with the article, amount and reason, hiding acknowledged ones', () => {
    const rejected: RejectedSale[] = [
      {
        ...pending('r1', '2026-10-08T12:05:00Z', { quantity: 2 }),
        reason: 'Product unavailable',
        rejectedAt: '2026-10-08T13:00:00Z',
      },
      {
        ...pending('r2', '2026-10-08T14:00:00Z', { productId: 'gone' }),
        reason: 'Insufficient stock',
        rejectedAt: '2026-10-08T14:30:00Z',
      },
      { ...pending('r3', '2026-10-07T10:00:00Z'), reason: 'x', rejectedAt: 'x', dismissed: true },
    ]
    const shown = refusedSales(rejected, names)
    expect(shown.map((s) => s.id)).toEqual(['r2', 'r1']) // most recent first
    expect(shown[0].name).toBe('Un article') // no longer in the cached stock
    expect(shown[1]).toMatchObject({ name: 'Jean droit modèle B', amount: 44000, quantity: 2 })
    expect(shown[1].reason).toMatch(/plus en stock/)
  })

  it('lists waiting sales oldest first', () => {
    const shown = waitingSales(
      [pending('w2', '2026-10-08T14:00:00Z'), pending('w1', '2026-10-08T09:00:00Z')],
      names,
    )
    expect(shown.map((s) => s.id)).toEqual(['w1', 'w2'])
    expect(shown[0].reason).toBeUndefined()
  })
})
