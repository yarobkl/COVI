import { createRestaurantQrGateway } from './gateway.mjs'

// Consultation publique des QR des tables, en lecture seule.
// COVI_RESTAURANT_QR_ENABLED doit être 'true' pour servir les cartes.
// SUPABASE_SERVICE_ROLE_KEY ne quitte jamais le serveur.
Deno.serve(createRestaurantQrGateway({
  COVI_RESTAURANT_QR_ENABLED: Deno.env.get('COVI_RESTAURANT_QR_ENABLED'),
  COVI_PUBLIC_ORIGIN: Deno.env.get('COVI_PUBLIC_ORIGIN') || 'https://covi-snowy.vercel.app',
  SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
  SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
}))
