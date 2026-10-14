import { createPublicCheckoutGateway } from './gateway.mjs'

// Fonction publique au niveau HTTP (pas de JWT client) : la passerelle contrôle l'origine, les
// quotas, Turnstile et chaque champ avant d'appeler les fonctions SQL réservées à la clé serveur.
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis par Supabase et restent côté serveur.
Deno.serve(
  createPublicCheckoutGateway({
    COVI_GATEWAY_ENABLED: Deno.env.get('COVI_GATEWAY_ENABLED'),
    COVI_PUBLIC_ORIGIN: Deno.env.get('COVI_PUBLIC_ORIGIN'),
    SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
    SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
    COVI_GATEWAY_PEPPER: Deno.env.get('COVI_GATEWAY_PEPPER'),
    COVI_TURNSTILE_SECRET: Deno.env.get('COVI_TURNSTILE_SECRET'),
  }),
)
