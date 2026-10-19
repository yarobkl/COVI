# COVI — API Stock (branche de developpement)

## Contrat
API privee (JWT utilisateur Supabase), **proprietaire** de la boutique exclusivement.
Aucune cle `service_role` n'est acceptee depuis un client. Les corrections ne
modifient ni les ventes ni les paiements.

- `GET /functions/v1/stock-api?shop_id=<uuid>&status=all&limit=50&offset=0` :
  liste les produits (maximum 100/page), `next_offset` pour la pagination.
- `POST /functions/v1/stock-api/adjust` :
  `{ "product_id": "<uuid>", "expected_quantity": 5, "quantity": 8,
  "reason": "restock", "note": "Livraison" }`.
  Motifs : `restock`, `loss`, `theft`, `count_error`.

Codes : 200 OK, 400 validation, 401 authentification, 403 autorisation, 404 boutique
introuvable, 409 stock modifie simultanement, 503 backend indisponible.

## Securite et coherence
L'Edge Function verifie l'utilisateur avec Supabase Auth, puis transmet son JWT
a PostgREST sous RLS (jamais de clé de service). La RPC SQL compare
`expected_quantity` sous verrou de ligne et delegue a
`adjust_product_stock`, qui preserve les restrictions pour pieces uniques,
le statut des produits et le journal `stock_movements`.
En conflit (409), relire le stock puis demander a l'utilisateur de confirmer la correction.

## Temps reel
La migration ajoute `public.products` a la publication `supabase_realtime`
(sans changer les politiques RLS). L'ecran Stock ecoute uniquement les
changements `shop_id` de la boutique ouverte, recharge l'etat serveur a
chaque evenement et desabonne la connexion a la fermeture.

## Activation (non executee automatiquement)
1. Appliquer et verifier la migration SQL sur une base de test.
2. Lancer les tests Node/Vitest et les tests SQL isoles.
3. Appliquer la migration en production uniquement apres validation de publication.
4. Deployer l'Edge Function `stock-api` avec `verify_jwt=true`.
5. Verifier `SUPABASE_URL` et `SUPABASE_ANON_KEY` comme variables privees serveur.
   `COVI_STOCK_API_ORIGINS` optionnelle, liste d'origines autorisees separees par virgules.
6. Tester les comptes proprietaire / autre boutique, des corrections concurrentes et deux onglets.

Le site actuel COVI est une application **Vite/React**, pas Next.js ; l'API
s'execute dans Supabase Edge Functions et le front conserve son architecture.
