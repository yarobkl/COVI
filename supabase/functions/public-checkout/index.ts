import { createPublicCheckoutGateway } from './gateway.mjs'
import { buildPublicCheckoutEnvironment } from './edgeConfig.mjs'

// COVI_PUBLIC_ORIGIN: public origin(s), comma-separated.
// COVI_GATEWAY_ENABLED: must be exactly "true" to accept requests.
// COVI_GATEWAY_PEPPER: independent random secret, at least 32 characters.
// COVI_TURNSTILE_SECRET: required for public order submissions.
// SUPABASE_SERVICE_ROLE_KEY: server-only, never exposed in browser bundles.
//
// Fail closed when any required security setting is absent. This change is
// staged on a dedicated SECURITY branch, not deployed automatically.
Deno.serve(
  createPublicCheckoutGateway(
    buildPublicCheckoutEnvironment((name) => Deno.env.get(name)),
  ),
)
