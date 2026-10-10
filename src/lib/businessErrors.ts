// Server refusals shared by every screen (sale, stock, arrivals, charges, sign-in): the database
// answers in English, the shop reads short French that says what to do. Each screen translates its
// own errors first, then asks here, then falls back to its general message.
import { isSubscriptionInactive, reportSubscriptionInactive } from './subscription'

const messageOf = (error: unknown) =>
  String(
    (error as { message?: unknown } | null | undefined)?.message ??
      (typeof error === 'string' ? error : ''),
  ).toLowerCase()

/** Exact text of the read-only banner (subscription suspended or over). */
export const READ_ONLY_TEXT =
  'Abonnement suspendu : vous pouvez consulter vos données, mais plus vendre ni modifier. Contactez COVI pour le renouveler.'

export const SUBSCRIPTION_INACTIVE_TEXT =
  'Abonnement suspendu : rien n’est enregistré. Contactez COVI pour le renouveler.'

/** « Votre abonnement couvre 2 boutiques. Pour en ajouter une, contactez COVI. » */
export function shopQuotaMessage(limit: number | null | undefined) {
  if (!limit || limit < 1)
    return 'Votre abonnement ne couvre pas d’autre boutique. Pour en ajouter une, contactez COVI.'
  return `Votre abonnement couvre ${limit} boutique${limit > 1 ? 's' : ''}. Pour en ajouter une, contactez COVI.`
}

/**
 * The French message for a refusal known to every screen, or null when it is not one of them.
 * A subscription refusal also switches the shop to read only (see lib/subscription.ts).
 */
export function businessErrorMessage(
  error: unknown,
  context: { shopLimit?: number | null } = {},
): string | null {
  const m = messageOf(error)
  if (!m) return null
  if (isSubscriptionInactive(error)) {
    reportSubscriptionInactive()
    return SUBSCRIPTION_INACTIVE_TEXT
  }
  if (m.includes('active subscription required'))
    return 'Votre abonnement n’est pas actif : impossible d’ajouter une boutique. Contactez COVI pour le renouveler.'
  if (m.includes('shop quota reached')) return shopQuotaMessage(context.shopLimit)
  if (m.includes('shop not found'))
    return 'Cette boutique n’est pas sur ce compte. Reconnectez-vous avec le bon compte, puis réessayez.'
  if (m.includes('authentication required'))
    return 'Votre session a pris fin. Reconnectez-vous, puis réessayez.'
  if (m.includes('admin access required'))
    return 'Accès réservé à l’équipe COVI. Connectez-vous avec un compte administrateur.'
  return null
}
