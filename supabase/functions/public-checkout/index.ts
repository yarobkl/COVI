import { createPublicCheckoutGateway } from './gateway.mjs'

// Fonction publique au niveau HTTP (pas de JWT client) : la passerelle contrôle l'origine, les
// quotas, Turnstile et chaque champ avant d'appeler les fonctions SQL réservées à la clé serveur.
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis par Supabase et restent côté serveur.
//
// Réglages (secrets de la fonction, tableau de bord Supabase → Edge Functions → Secrets) :
//   COVI_TURNSTILE_SECRET  clé secrète Cloudflare Turnstile (obligatoire pour accepter des demandes)
//   COVI_GATEWAY_ENABLED   « false » coupe immédiatement tout le canal public (arrêt d'urgence)
//   COVI_PUBLIC_ORIGIN     origines autorisées, séparées par des virgules (défaut : le site officiel)
//   COVI_GATEWAY_PEPPER    sel des empreintes de quotas (défaut : dérivé de la clé serveur)
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

Deno.serve(
  createPublicCheckoutGateway({
    COVI_GATEWAY_ENABLED: Deno.env.get('COVI_GATEWAY_ENABLED') === 'false' ? 'false' : 'true',
    COVI_PUBLIC_ORIGIN: Deno.env.get('COVI_PUBLIC_ORIGIN') || 'https://covi-snowy.vercel.app',
    SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
    SUPABASE_SERVICE_ROLE_KEY: serviceKey,
    COVI_GATEWAY_PEPPER: Deno.env.get('COVI_GATEWAY_PEPPER') || 'covi-quota:' + serviceKey,
    COVI_TURNSTILE_SECRET: Deno.env.get('COVI_TURNSTILE_SECRET'),
  }),
)
