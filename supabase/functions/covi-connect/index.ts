import { createWebsiteConnectGateway } from './gateway.mjs'

// Gateway tests both owner JWT and individual website keys. Do not disable auth checks.
Deno.serve(createWebsiteConnectGateway({
  SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
  SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY'),
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  COVI_SITE_MANAGEMENT_ORIGIN: Deno.env.get('COVI_SITE_MANAGEMENT_ORIGIN')
}))
