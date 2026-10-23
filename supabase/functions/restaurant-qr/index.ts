import { createRestaurantQrGateway } from './gateway.mjs'

// Public read-only table menu. Owner requested activation on the two official COVI hosts.
// Never include secret keys in frontend output or logs.
// Explicit COVI_RESTAURANT_QR_ENABLED=false still disables the gateway immediately.
Deno.serve(
  createRestaurantQrGateway({
    COVI_RESTAURANT_QR_ENABLED: Deno.env.get('COVI_RESTAURANT_QR_ENABLED') ?? 'true',
    COVI_PUBLIC_ORIGIN:
      Deno.env.get('COVI_PUBLIC_ORIGIN') ??
      'https://covi-snowy.vercel.app,https://covi.eliebakala.workers.dev',
    SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
    SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  }),
)
