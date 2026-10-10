/** Translates a Supabase auth/RPC error into a French message for the shop owner. */
export function authError(error: unknown) {
  const m = String((error as { message?: unknown } | null)?.message || '').toLowerCase()
  if (m.includes('invalid login') || m.includes('invalid credentials'))
    return 'E-mail ou mot de passe incorrect. Vérifiez et réessayez.'
  if (m.includes('email not confirmed'))
    return 'Confirmez d’abord votre adresse : ouvrez l’e-mail de COVI et choisissez le lien. Puis revenez ici.'
  if (m.includes('already registered') || m.includes('already been registered'))
    return 'Cette adresse a déjà un compte. Connectez-vous plutôt.'
  // Only a password that is too short; other password errors get the general message.
  if (m.includes('password') && (m.includes('at least') || m.includes('short') || /\b6\b/.test(m)))
    return 'Mot de passe trop court : 6 caractères minimum.'
  if (m.includes('shop name is required')) return 'Indiquez le nom de la boutique.'
  if (m.includes('network') || m.includes('fetch'))
    return 'Pas de réseau. Réessayez quand la connexion revient.'
  return 'Ça n’a pas marché. Vérifiez l’e-mail et le mot de passe, puis réessayez.'
}
