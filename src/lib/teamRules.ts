// Règles de la caisse multi-caissiers partagées avec la base (prix minimal, format du PIN) et
// messages dans les mots de la boutique. Aucun appel réseau ici (testable sans Supabase).
import { fcfa } from './format'

/** Result of a PIN check done by the server (verify_my_pin, set_my_pin, open_till_session). */
export type PinResult =
  | { status: 'ok' }
  | { status: 'invalid'; attempts_left: number }
  | { status: 'locked'; retry_after: string }
  | { status: 'not_set' }

/**
 * Lowest unit price a cashier may charge: displayed price minus their maximum discount, rounded
 * to the nearest franc, never above the displayed price (same rule as min_unit_price in SQL).
 * `null` = no minimum (the owner selling in their own name).
 */
export function minUnitPrice(displayed: number, maxDiscountPct: number | null | undefined) {
  if (maxDiscountPct === null || maxDiscountPct === undefined) return null
  // Same rounding as PostgreSQL round(numeric) for positive amounts (half up). Multiplying
  // before dividing keeps 15 × 90 / 100 = 13.5 exact in floating point.
  const floor = Math.round((displayed * (100 - maxDiscountPct)) / 100)
  return Math.min(displayed, floor)
}

/** Same refusals as member_pin_assert_strength: 4 to 6 digits, nothing trivial. */
export function pinProblem(pin: string): string | null {
  if (!/^[0-9]{4,6}$/.test(pin)) return 'Le code PIN compte 4 à 6 chiffres.'
  const digits = [...pin].map(Number)
  const steps = digits.slice(1).map((d, i) => d - digits[i])
  const trivial =
    /^(.)\1+$/.test(pin) ||
    steps.every((s) => s === 1) ||
    steps.every((s) => s === -1) ||
    /^(..)\1+$/.test(pin) ||
    /^(...)\1$/.test(pin) ||
    ['112233', '2580', '258000', '1122', '1004', '696969', '159753'].includes(pin)
  return trivial ? 'Ce code est trop facile à deviner. Choisissez-en un autre.' : null
}

/** Minutes left before a locked PIN can be tried again (rounded up, at least 1). */
export const minutesUntil = (iso: string, now = Date.now()) =>
  Math.max(1, Math.ceil((new Date(iso).getTime() - now) / 60000))

/** What to say after a refused PIN. */
export function pinResultMessage(result: PinResult): string {
  switch (result.status) {
    case 'ok':
      return ''
    case 'invalid':
      return result.attempts_left > 1
        ? `Code PIN incorrect. Encore ${result.attempts_left} essais.`
        : 'Code PIN incorrect. Dernier essai avant le blocage.'
    case 'locked':
      return 'Trop d’essais. Réessayez dans 15 minutes.'
    case 'not_set':
      return 'Ce caissier n’a pas encore choisi son code PIN. Il doit l’ouvrir sur son téléphone.'
  }
}

/** What to say after a refused OWNER PIN (leaving counter mode, changing it). */
export function ownerPinResultMessage(result: PinResult): string {
  switch (result.status) {
    case 'ok':
      return ''
    case 'invalid':
      return result.attempts_left > 1
        ? `Code du responsable incorrect. Encore ${result.attempts_left} essais.`
        : 'Code du responsable incorrect. Dernier essai avant le blocage.'
    case 'locked':
      return 'Trop d’essais. Le code du responsable est bloqué 15 minutes.'
    case 'not_set':
      return 'Le responsable n’a pas encore choisi son code.'
  }
}

const messageOf = (error: unknown) =>
  String((error as { message?: unknown } | null | undefined)?.message ?? error ?? '')

/** Server refusals of the team functions, in the shop's words. */
export function teamErrorMessage(error: unknown): string {
  const m = messageOf(error).toLowerCase()
  if (m.includes('invalid pin format')) return 'Le code PIN compte 4 à 6 chiffres.'
  if (m.includes('owner pin required'))
    return 'Choisissez d’abord votre code de responsable : il sera demandé pour quitter le comptoir.'
  if (m.includes('till session invalid'))
    return 'La caisse de ce caissier est fermée ou a expiré. Choisissez à nouveau qui tient la caisse.'
  if (m.includes('pin too simple'))
    return 'Ce code est trop facile à deviner. Choisissez-en un autre.'
  if (m.includes('owner cannot join own shop'))
    return 'Ce code est pour un caissier : vous êtes déjà le responsable de cette boutique.'
  if (m.includes('invalid display name'))
    return 'Indiquez le prénom du caissier (60 lettres au plus).'
  if (m.includes('invalid discount')) return 'La remise maximale va de 0 à 100 %.'
  if (m.includes('too many pending invites'))
    return 'Trop d’invitations en attente. Annulez-en une avant d’en créer une autre.'
  if (m.includes('invite already used')) return 'Cette invitation a déjà été utilisée.'
  if (
    m.includes('member not found') ||
    m.includes('invite not found') ||
    m.includes('shop not found')
  )
    return 'Vous n’avez pas accès à cette boutique. Demandez au responsable.'
  if (m.includes('authentication required'))
    return 'Votre session a pris fin. Reconnectez-vous puis réessayez.'
  return 'Ça n’a pas marché. Vérifiez le réseau puis réessayez.'
}

/** Message shown when a cashier's price is under their allowed minimum. */
export const belowMinimumMessage = (minimum: number) =>
  `Ce prix est en dessous du minimum autorisé (${fcfa(minimum)} FCFA). Demandez au responsable.`

/** « mercredi 14:30 » : expiry of an invite, in the shop's words. */
export const inviteTime = (iso: string) =>
  new Date(iso).toLocaleString('fr-FR', {
    weekday: 'long',
    hour: '2-digit',
    minute: '2-digit',
  })

/** Text sent to the future cashier (WhatsApp friendly, no link to click). */
export function inviteMessage(shopName: string, invite: { code: string; expires_at: string }) {
  return [
    `Bonjour, voici votre code pour tenir la caisse de ${shopName} sur COVI : ${invite.code}`,
    '1. Ouvrez COVI et créez votre compte (votre adresse e-mail et un mot de passe à vous).',
    '2. Touchez « J’ai un code de caissier » et tapez ce code.',
    '3. Choisissez votre code PIN : 4 à 6 chiffres, ne le donnez à personne, même pas à moi.',
    `Le code marche une seule fois, jusqu’à ${inviteTime(invite.expires_at)}.`,
  ].join('\n')
}
