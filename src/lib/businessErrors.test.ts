import { afterEach, describe, expect, it, vi } from 'vitest'
import { arrivalSaveError } from '../features/arrivals/arrivalForms'
import { authError } from '../features/auth/authErrors'
import { expenseSaveError } from '../features/expenses/expenseForm'
import { saleErrorMessage } from '../features/sale/saleErrors'
import { productSaveError } from '../features/stock/productForm'
import {
  businessErrorMessage,
  shopQuotaMessage,
  SUBSCRIPTION_INACTIVE_TEXT,
} from './businessErrors'
import { onSubscriptionInactive } from './subscription'

const err = (message: string, code = 'P0001') => ({ message, code })

const screens = {
  vente: (e: unknown) => saleErrorMessage(e),
  stock: productSaveError,
  arrivages: arrivalSaveError,
  charges: (e: unknown) => expenseSaveError(e, 'new'),
  connexion: authError,
}

afterEach(() => vi.restoreAllMocks())

describe('shared business errors, on every screen', () => {
  const cases: [string, string][] = [
    ['Subscription inactive: shop is read-only', SUBSCRIPTION_INACTIVE_TEXT],
    [
      'Active subscription required',
      'Votre abonnement n’est pas actif : impossible d’ajouter une boutique. Contactez COVI pour le renouveler.',
    ],
    [
      'Shop quota reached',
      'Votre abonnement ne couvre pas d’autre boutique. Pour en ajouter une, contactez COVI.',
    ],
    [
      'Shop not found',
      'Cette boutique n’est pas sur ce compte. Reconnectez-vous avec le bon compte, puis réessayez.',
    ],
    [
      'Admin access required',
      'Accès réservé à l’équipe COVI. Connectez-vous avec un compte administrateur.',
    ],
  ]
  for (const [name, translate] of Object.entries(screens))
    for (const [server, french] of cases)
      it(`${name}: « ${server} »`, () => {
        expect(translate(err(server))).toBe(french)
      })

  it('« Authentication required »: reconnect (the sale says to validate again)', () => {
    expect(businessErrorMessage(err('Authentication required', '42501'))).toBe(
      'Votre session a pris fin. Reconnectez-vous, puis réessayez.',
    )
    expect(productSaveError(err('Authentication required'))).toBe(
      'Votre session a pris fin. Reconnectez-vous, puis réessayez.',
    )
    expect(expenseSaveError(err('Authentication required'), 'edit')).toBe(
      'Votre session a pris fin. Reconnectez-vous, puis réessayez.',
    )
    expect(saleErrorMessage(err('Authentication required'))).toBe(
      'Votre session a pris fin. Reconnectez-vous, puis validez la vente à nouveau.',
    )
  })

  it('« Shop quota reached » says how many shops the subscription covers', () => {
    expect(businessErrorMessage(err('Shop quota reached'), { shopLimit: 2 })).toBe(
      'Votre abonnement couvre 2 boutiques. Pour en ajouter une, contactez COVI.',
    )
    expect(shopQuotaMessage(1)).toBe(
      'Votre abonnement couvre 1 boutique. Pour en ajouter une, contactez COVI.',
    )
  })

  it('a subscription refusal switches the shop to read only', async () => {
    const listener = vi.fn()
    const stop = onSubscriptionInactive(listener)
    saleErrorMessage(err('Subscription inactive: shop is read-only'))
    await Promise.resolve()
    expect(listener).toHaveBeenCalledTimes(1)
    stop()
  })

  it('unknown errors keep each screen’s own message', () => {
    expect(businessErrorMessage(err('boom'))).toBeNull()
    expect(expenseSaveError(new Error('boom'), 'delete')).toBe(
      'Pas supprimée : le réseau ne répond pas. Réessayez.',
    )
  })
})

describe('cart errors (docs/contrat-panier.md)', () => {
  const cart: [string, string][] = [
    [
      'Cart items must be a JSON array',
      'Le panier est mal enregistré. Videz-le, ajoutez à nouveau les articles, puis validez.',
    ],
    [
      'Invalid cart item',
      'Le panier est mal enregistré. Videz-le, ajoutez à nouveau les articles, puis validez.',
    ],
    [
      'Cart must contain between 1 and 50 items',
      'Un panier compte de 1 à 50 articles. Retirez ou ajoutez des articles, puis validez.',
    ],
    [
      'Duplicate product in cart',
      'Cet article est deux fois dans le panier. Gardez une seule ligne et changez la quantité.',
    ],
    ['Sale total too large', 'Le total est trop élevé. Vérifiez les prix et les quantités.'],
    [
      'Cannot mix test and real products',
      'Les articles d’exemple ne se vendent pas avec les vrais. Faites deux ventes séparées.',
    ],
    ['Sale operation id is required', 'Ça n’a pas marché. Validez la vente une nouvelle fois.'],
    ['Invalid payment method', 'Choisissez comment la cliente a payé.'],
    ['Quantity must be positive', 'Indiquez au moins 1 pièce.'],
    ['Sold price cannot be negative', 'Indiquez le prix auquel vous avez vendu.'],
    ['Product unavailable', 'Cet article n’est plus en stock. Il a peut-être déjà été vendu.'],
    ['Unique piece quantity must be 1', 'C’est une pièce unique : la quantité est 1.'],
    ['Insufficient stock', 'Il n’en reste pas assez. Baissez la quantité.'],
  ]
  for (const [server, french] of cart)
    it(`« ${server} »`, () => {
      expect(saleErrorMessage(err(server))).toBe(french)
    })
})
