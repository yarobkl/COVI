import { configuredPublicGatewayEnv, createPublicCheckoutGateway } from './gateway.mjs'

// Fonction publique au niveau HTTP (pas de JWT client) : la passerelle contrôle l'origine, les
// quotas, Turnstile et chaque champ avant d'appeler les fonctions SQL réservées à la clé serveur.
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis par Supabase et restent côté serveur.
//
// Réglages (secrets de la fonction, tableau de bord Supabase → Edge Functions → Secrets) :
//   COVI_TURNSTILE_SECRET  clé secrète Cloudflare Turnstile (obligatoire pour accepter des demandes)
//   COVI_GATEWAY_ENABLED   'true' explicitly required; absence disables public access
//   COVI_PUBLIC_ORIGIN     allowlisted HTTPS origins, explicitly configured
//   COVI_GATEWAY_PEPPER    independent random secret (32+ characters), NEVER derived from service key
//
// SECURITY: no silent production defaults for public access or privileges.
// Keep the deployed function unchanged until the operator confirms all secrets
// and the gateway is tested in staging.
Deno.serve(
  createPublicCheckoutGateway(
    configuredPublicGatewayEnv({
      COVI_GATEWAY_ENABLED: Deno.env.get('COVI_GATEWAY_ENABLED'),
      COVI_PUBLIC_ORIGIN: Deno.env.get('COVI_PUBLIC_ORIGIN'),
      SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
      SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
      COVI_GATEWAY_PEPPER: Deno.env.get('COVI_GATEWAY_PEPPER'),
      COVI_TURNSTILE_SECRET: Deno.env.get('COVI_TURNSTILE_SECRET'),
    }),
  ),
)
