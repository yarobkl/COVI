/** Translates a Supabase auth/RPC error into a French message for the shop owner. */
export function authError(error: unknown) {
  const m = String((error as { message?: unknown } | null)?.message || '').toLowerCase()
  if (m.includes('invalid login') || m.includes('invalid credentials'))
    return 'Adresse e-mail ou mot de passe incorrect.'
  if (m.includes('email not confirmed'))
    return 'Confirmez votre adresse e-mail avant de vous connecter.'
  if (m.includes('already registered') || m.includes('already been registered'))
    return 'Un compte existe déjà avec cette adresse e-mail.'
  if (m.includes('password')) return 'Le mot de passe doit contenir au moins 6 caractères.'
  if (m.includes('network') || m.includes('fetch'))
    return 'Connexion impossible. Vérifiez Internet puis réessayez.'
  return 'Une erreur est survenue. Vérifiez les informations puis réessayez.'
}
