# Intégration sécurisée de la caisse COVI — 17 octobre 2026

> **Branche de travail isolée** fondée sur le commit de production `ba8c99b7947686b22705aed3df1ab1ab6628c60a` (`claude/caisse-multi-caissiers`).
>
> **Pas de déploiement, pas de migrations, pas de fusion automatique.**

## Pourquoi ne pas merger la PR #22 telle quelle

La PR #22 (`feature/covi-stock-central-omnichannel`) a divergé de la production : lors du contrôle, elle était 361 commits devant et 218 derrière la branche qui alimente réellement Vercel.

La version de production contient déjà : commandes clients et QR sociaux, équipe et caissiers avec PIN, panier multiarticles, reçus automatiques, protections d'encaissement, stockage des photos, Edge Function `public-checkout`, champs de localisation, journal des mouvements de stock et certaines intégrations de paiement. La branche #22 utilise parallèlement d'autres tables et RPC expérimentales (`checkout_orders`, `stock_categories`, etc.), absentes de la base publiée. **Ne jamais importer ces migrations expérimentales sans conception de compatibilité.**

## Objectif de la branche

Reprendre **seulement** les améliorations manquantes et les correctifs de sécurité validés, en préservant :

- les comptes et l'authentification existants, notamment Google/Facebook ;
- le suivi des caissiers/PIN et l'identification nominative de l'encaissement ;
- la confirmation manuelle de l'argent reçu (ne jamais affirmer avoir vérifié automatiquement une transaction Mobile Money) ;
- les stocks et les ventes réelles, y compris les historiques et les rapports ;
- la direction artistique **« Le Cahier »**, feuille Seyès, stylo, typographies et fluidité mobile ;
- le fonctionnement du QR/lien client et ses références ;
- le contrôle des accès, le stockage privé, les reçus durables et l'idempotence.

## Vérifications avant la promotion

1. Faire l'inventaire métier `production` ↔ `feature/covi-stock-central-omnichannel` et identifier les comportements réellement absents.
2. Corriger les limites de sécurité de l'entrée publique (proxy/IP fiable, quotas, tests anti-abus).
3. Définir conservation et suppression sécurisée des coordonnées client et des photos, sans effacer les reçus/écritures obligatoires.
4. Compléter la renégociation de prix avec accord du client et tests d'encaissement.
5. Vérifier que l'historique, les statistiques et les stocks ont des totaux compatibles.
6. Exécuter tests de concurrence, Auth/PostgREST, TypeScript, lint, formatage, tests UI mobile et scénario de panne réseau.
7. Réviser les migrations **additives uniquement**, avec sauvegarde, restauration et plan de retour arrière.
8. Faire une revue finale **GO/NO-GO** avant toute modification de la base, de la branche de production ou de Vercel.

## État vérifié

- GitHub : trois workflows du dernier commit de la branche #22 ont réussi (Windows, contrôles isolés, Supabase natif). Ce succès n'atteste **pas** la compatibilité des deux lignes de code.
- Vercel : `covi-snowy.vercel.app` pointe vers un déploiement prêt du commit `ba8c99b7…`, branche `claude/caisse-multi-caissiers`.
- Supabase : tables expérimentales `stock_categories`, `checkout_orders`, `checkout_order_lines` et `manual_payment_confirmations` absentes, tandis que `public_orders`, `shop_members`, `sales`, `products` et `stock_movements` existent.
- Aucune donnée réelle modifiée lors de ce contrôle.

**État de livraison : branche de préparation uniquement. Ne pas présenter cette étape comme un déploiement réussi.**
