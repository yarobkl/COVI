/** An explicit opt-in is necessary but NOT sufficient for an isolated
 * checkout build: it must also have its OWN Supabase project and public key.
 * Never allow the existing app's production fallback to silently take over.
 */
export function checkoutFeatureConfigured(
  enabled: unknown,
  supabaseUrl: unknown,
  publicKey: unknown,
): boolean {
  if (enabled !== 'true' || typeof supabaseUrl !== 'string' || typeof publicKey !== 'string')
    return false

  try {
    const url = new URL(supabaseUrl)
    const local = ['localhost', '127.0.0.1'].includes(url.hostname)
    // The main COVI project is a live database. A build flag alone must
    // never turn experimental checkout on against that project's real data.
    // Keep this explicit block even when a publishable browser key is used.
    const productionHost = 'bmbwmwgfzrijglzcgjut.supabase.co'
    if (url.hostname.toLowerCase() === productionHost) return false
    if (
      (!local && url.protocol !== 'https:') ||
      (local && !['http:', 'https:'].includes(url.protocol)) ||
      url.username ||
      url.password ||
      url.pathname !== '/' ||
      url.search ||
      url.hash
    )
      return false

    if (publicKey.startsWith('sb_secret_')) return false
    if (publicKey.startsWith('sb_publishable_')) return publicKey.length >= 28

    // Older Supabase configurations use a JWT anon key. Reject service_role
    // JWTs from VITE_* configuration: those must never enter a browser bundle.
    const parts = publicKey.split('.')
    if (parts.length !== 3) return false
    const base64 = parts[1].replace(/-/g, '+').replace(/_/g, '/')
    const payload: unknown = JSON.parse(atob(base64))
    return Boolean(
      payload && typeof payload === 'object' && 'role' in payload && payload.role === 'anon',
    )
  } catch {
    return false
  }
}

/** Disabled by default, including in mistakenly configured preview builds.
 * Never change login/OAuth or production storefront behaviour from this gate.
 */
export const categoryCheckoutEnabled = checkoutFeatureConfigured(
  import.meta.env.VITE_COVI_CATEGORY_CHECKOUT_ENABLED,
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY,
)
