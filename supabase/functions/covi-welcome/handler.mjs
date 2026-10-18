const OAUTH_PROVIDERS = new Set(['google', 'facebook'])
const MAX_WELCOME_AGE_MS = 24 * 60 * 60 * 1000

/**
 * OAuth already establishes identity with the provider. This is a welcome receipt,
 * not a fake second confirmation of the user's email address.
 */
export function welcomeEligibility(user, now = Date.now()) {
  if (!user || !OAUTH_PROVIDERS.has(user.app_metadata?.provider))
    return { allowed: false, reason: 'not-oauth' }
  if (typeof user.email !== 'string' || !user.email.includes('@') || !user.email_confirmed_at)
    return { allowed: false, reason: 'unverified-email' }
  if (user.app_metadata?.covi_welcome_email_sent_at)
    return { allowed: false, reason: 'already-sent' }

  const created = Date.parse(user.created_at ?? '')
  if (!Number.isFinite(created) || created > now || now - created > MAX_WELCOME_AGE_MS)
    return { allowed: false, reason: 'not-new-account' }
  return { allowed: true, reason: 'new-oauth-account' }
}

export function welcomeMail(user) {
  const platform = user.app_metadata.provider === 'facebook' ? 'Facebook' : 'Google'
  const firstName =
    typeof user.user_metadata?.first_name === 'string'
      ? user.user_metadata.first_name.trim().slice(0, 80)
      : ''
  const greeting = firstName ? `Bonjour ${firstName},` : 'Bonjour,'
  return {
    to: [user.email],
    subject: 'Bienvenue sur COVI — votre compte a été créé',
    text: `${greeting}

Votre compte COVI a bien été créé grâce à votre connexion ${platform}.

Vous pouvez maintenant choisir votre secteur d'activité et configurer votre établissement sur COVI.

Si vous n'êtes pas à l'origine de cette inscription, contactez l'assistance COVI.

COVI — Outils de gestion opérationnelle, financière et humaine des PME.`,
  }
}

export async function dispatchWelcome({ getUser, sendMail, markSent, token, now = Date.now() }) {
  if (typeof token !== 'string' || !token.trim()) return { status: 401, reason: 'unauthorized' }
  const user = await getUser(token)
  if (!user) return { status: 401, reason: 'unauthorized' }
  const eligibility = welcomeEligibility(user, now)
  if (!eligibility.allowed) return { status: 200, reason: eligibility.reason }

  const idempotencyKey = `covi-welcome/${user.id}`
  const receipt = await sendMail(welcomeMail(user), idempotencyKey)
  if (!receipt || !receipt.id) return { status: 503, reason: 'mail-not-accepted' }
  await markSent(user, new Date(now).toISOString())
  return { status: 200, reason: 'sent' }
}
