import { createOpenPayHandler } from './handler.mjs'

// Paiement Mobile Money des commandes via OpenPay. Aucun secret ici : la clé API OpenPay de chaque
// boutique est dans Supabase Vault ; SUPABASE_URL, SUPABASE_ANON_KEY et SUPABASE_SERVICE_ROLE_KEY
// sont fournis par Supabase et restent côté serveur.
//
// Réglages facultatifs (secrets de la fonction) :
//   COVI_OPENPAY_ENABLED  « true » active les paiements Mobile Money (coupés par défaut en V1)
//   COVI_PUBLIC_ORIGIN    origines autorisées, séparées par des virgules (défaut : le site officiel)
//
// URL de callback à renseigner dans le tableau de bord OpenPay de chaque boutique :
//   https://<projet>.supabase.co/functions/v1/openpay?action=callback
Deno.serve(
  createOpenPayHandler({
    // V1 : coupé par défaut (paiement direct prévu pour la V2). COVI_OPENPAY_ENABLED=true le rallume.
    COVI_OPENPAY_ENABLED: Deno.env.get('COVI_OPENPAY_ENABLED') === 'true' ? 'true' : 'false',
    COVI_PUBLIC_ORIGIN: Deno.env.get('COVI_PUBLIC_ORIGIN') || 'https://covi-snowy.vercel.app',
    SUPABASE_URL: Deno.env.get('SUPABASE_URL'),
    // Clé publique (la même que le site) : seule la session de la boutique donne des droits.
    SUPABASE_ANON_KEY:
      Deno.env.get('COVI_PUBLISHABLE_KEY') || 'sb_publishable_DoBPQwskWNP7Wo8sjbWUwA_BrDO4z0m',
    SUPABASE_SERVICE_ROLE_KEY: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    OPENPAY_API_BASE: 'https://api.openpay-cg.com',
  }),
)
