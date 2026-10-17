import { createRestaurantGuestGateway } from './gateway.mjs'

// Customer multi-phone actions are closed unless explicitly enabled.
// Never set COVI_RESTAURANT_GUEST_ENABLED in production without security approval.
Deno.serve(createRestaurantGuestGateway({
  COVI_RESTAURANT_GUEST_ENABLED: Deno.env.get('COVI_RESTAURANT_GUEST_ENABLED'),
  COVI_PUBLIC_ORIGIN: Deno.env.get('COVI_PUBLIC_ORIGIN') || 'https://covi-snowy.vercel.app',
  SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  COVI_GATEWAY_PEPPER: Deno.env.get('COVI_GATEWAY_PEPPER'),
  COVI_TURNSTILE_SECRET: Deno.env.get('COVI_TURNSTILE_SECRET'),
}))
