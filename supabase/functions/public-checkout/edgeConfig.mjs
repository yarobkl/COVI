/** Public order gateway environment assembled on the trusted Edge server.
 * Fail closed: missing activation or missing independent HMAC secret means
 * the public endpoints cannot be enabled accidentally.
 * The service-role key and quota pepper must NEVER appear in the browser.
 */
export function buildPublicCheckoutEnvironment(getEnv) {
  return {
    COVI_GATEWAY_ENABLED: getEnv('COVI_GATEWAY_ENABLED') === 'true' ? 'true' : 'false',
    COVI_PUBLIC_ORIGIN:
      getEnv('COVI_PUBLIC_ORIGIN') || 'https://covi-snowy.vercel.app',
    SUPABASE_URL: getEnv('SUPABASE_URL') || '',
    SUPABASE_SERVICE_ROLE_KEY: getEnv('SUPABASE_SERVICE_ROLE_KEY') || '',
    // Do not derive the quota HMAC pepper from the service-role JWT.
    // An independent random secret allows key rotation without changing
    // source quotas or unnecessarily coupling two security domains.
    COVI_GATEWAY_PEPPER: getEnv('COVI_GATEWAY_PEPPER') || '',
    COVI_TURNSTILE_SECRET: getEnv('COVI_TURNSTILE_SECRET') || '',
  }
}
