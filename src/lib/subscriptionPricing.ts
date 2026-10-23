/** Tarifs provisoires COVI SaaS, en FCFA (XAF) entiers. */
export const FIRST_SHOP_MONTHLY_XAF = 10_000
export const EXTRA_SHOP_MONTHLY_XAF = 5_000

/**
 * Prix d'un abonnement pour un quota de boutiques.
 * Le prix d'une facture émise doit être figé en base et non recalculé avec ce module.
 */
export function monthlySubscriptionXaf(shopLimit: number): number {
  if (!Number.isSafeInteger(shopLimit) || shopLimit < 1) {
    throw new RangeError('Le nombre de boutiques doit être un entier positif')
  }
  const amount = FIRST_SHOP_MONTHLY_XAF + (shopLimit - 1) * EXTRA_SHOP_MONTHLY_XAF
  if (!Number.isSafeInteger(amount)) {
    throw new RangeError('Montant hors limites')
  }
  return amount
}

/** Différence mensuelle pour une augmentation de quota (hors prorata). */
export function monthlyUpgradeDifferenceXaf(currentLimit: number, requestedLimit: number): number {
  if (requestedLimit < currentLimit) {
    throw new RangeError('Le quota demandé ne peut pas être inférieur au quota actuel')
  }
  return monthlySubscriptionXaf(requestedLimit) - monthlySubscriptionXaf(currentLimit)
}
