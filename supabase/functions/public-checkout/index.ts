import { createPublicCheckoutGateway } from './gateway.mjs'

// Deliberately no Authorization/JWT requirement for customers, but the gateway
// validates origin, HMAC quotas, Turnstile and every input before privileged RPCs.
// Its backend secret is never sent to web clients.
Deno.serve(
  createPublicCheckoutGateway({
    COVI_GATEWAY_ENABLED: Deno.env.get('COVI_GATEWAY_ENABLED'),
    COVI_PUBLIC_ORIGIN: Deno.env.get('COVI_PUBLIC_ORIGIN'),
    SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
    COVI_SUPABASE_SECRET_KEY: Deno.env.get('COVI_SUPABASE_SECRET_KEY'),
    COVI_GATEWAY_PEPPER: Deno.env.get('COVI_GATEWAY_PEPPER'),
    COVI_TURNSTILE_SECRET: Deno.env.get('COVI_TURNSTILE_SECRET'),
  }),
)
