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

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (symbol) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[symbol],
  )
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
    html: `<!doctype html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:32px 12px;background:#f5f2ea;font-family:Arial,Helvetica,sans-serif;color:#282623;">
<main style="max-width:560px;margin:0 auto;background:#fffdf8;border:1px solid #e2dbcb;border-radius:16px;overflow:hidden;">
<header style="background:#faf5e9;padding:25px 30px;border-bottom:1px solid #e8e2d7;">
<p style="color:#997444;letter-spacing:.15em;font-weight:bold;font-size:13px;">COVI · COMMERCE &amp; VIE</p>
<p style="font-size:12px;color:#676258;">OUTILS DE GESTION OPÉRATIONNELLE, FINANCIÈRE ET HUMAINE DES PME</p></header>
<section style="padding:30px">
<p style="font-size:15px;">${escapeHtml(greeting)}</p>
<h1 style="font-size:26px;margin:0 0 16px;">Bienvenue dans votre espace COVI.</h1>
<p style="line-height:1.7;">Votre compte a bien été créé avec ${platform}. Vous pouvez à présent préparer la gestion de votre boutique, de votre restaurant ou de votre salon de coiffure, dans un espace pensé pour votre quotidien.</p>
<p style="line-height:1.7;">Choisissez votre secteur d’activité, renseignez l’adresse de votre établissement et finalisez sa configuration.</p>
<p style="margin:28px 0;"><a href="https://covi-snowy.vercel.app" style="display:inline-block;background:#233b33;color:white;padding:15px 22px;text-decoration:none;border-radius:9px;font-weight:bold;">Accéder à mon espace COVI</a></p>
<hr style="border:none;border-top:1px solid #e6e0d2;margin:26px 0">
<p style="font-size:13px;line-height:1.6;color:#655f55;">Si vous n’avez pas créé ce compte, contactez l’assistance COVI et sécurisez votre accès ${platform}. Ce message confirme une inscription et ne demande aucun mot de passe.</p>
</section><footer style="background:#f8f5ed;padding:18px 30px;font-size:12px;color:#6c665c;">Puissant derrière. Extrêmement simple devant.</footer>
</main></body></html>`,
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
