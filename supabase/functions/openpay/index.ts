import { createOpenPayHandler } from './handler.mjs'

// Paiement Mobile Money des commandes via OpenPay. Aucun secret ici : la clé API OpenPay de chaque
// boutique est dans Supabase Vault ; SUPABASE_URL, SUPABASE_ANON_KEY et SUPABASE_SERVICE_ROLE_KEY
// sont fournis par Supabase et restent côté serveur.
//
// Réglages facultatifs (secrets de la fonction) :
//   COVI_OPENPAY_ENABLED  « false » coupe immédiatement les paiements Mobile Money (arrêt d'urgence)
//   COVI_PUBLIC_ORIGIN    origines autorisées, séparées par des virgules (défaut : le site officiel)
//
// URL de callback à renseigner dans le tableau de bord OpenPay de chaque boutique :
//   https://<projet>.supabase.co/functions/v1/openpay?action=callback
Deno.serve(
  createOpenPayHandler({
    COVI_OPENPAY_ENABLED: Deno.env.get('COVI_OPENPAY_ENABLED') === 'false' ? 'false' : 'true',
    COVI_PUBLIC_ORIGIN: Deno.env.get('COVI_PUBLIC_ORIGIN') || 'https://covi-snowy.vercel.app',
    SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
    SUPABASE_ANON_KEY: Deno.env.get('SUPABASE_ANON_KEY'),
    SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    OPENPAY_API_BASE: 'https://api.openpay-cg.com',
  }),
)
