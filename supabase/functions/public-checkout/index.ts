import { createPublicCheckoutGateway, resolvePublicCheckoutEnvironment } from './gateway.mjs'

// Fonction publique au niveau HTTP (pas de JWT client) : la passerelle contrôle l'origine, les
// quotas, Turnstile et chaque champ avant d'appeler les fonctions SQL réservées à la clé serveur.
// SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournis par Supabase et restent côté serveur.
//
// Réglages (secrets de la fonction, tableau de bord Supabase → Edge Functions → Secrets) :
//   COVI_TURNSTILE_SECRET  clé secrète Cloudflare Turnstile (obligatoire pour accepter des demandes)
//   COVI_GATEWAY_ENABLED   doit valoir exactement « true » pour activer le canal
//                          absent ou différent de « true » = arrêt d'urgence
//   COVI_PUBLIC_ORIGIN     origines https explicitement autorisées, sans valeur par défaut
//   COVI_GATEWAY_PEPPER    secret aléatoire indépendant >= 32 caractères, obligatoire
// Important : configurer ces trois réglages AVANT tout futur déploiement.
// Sans eux, le canal est volontairement fermé : aucun service n'est activé implicitement.
Deno.serve(
  createPublicCheckoutGateway(resolvePublicCheckoutEnvironment((name) => Deno.env.get(name))),
)
