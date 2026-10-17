# SQL expérimental COVI — NE PAS APPLIQUER

Ces fichiers sont des **brouillons de conception**. Ils sont volontairement placés dans `supabase/sql-drafts/` et **non** dans `supabase/migrations/`.

Une commande standard de migration Supabase ne doit pas les appliquer. Ne jamais les déplacer dans `supabase/migrations/`, les utiliser dans `supabase db push` ni les exécuter sur le projet de production COVI sans avoir validé les tests et obtenu une autorisation explicite.

Ordre **prévisionnel** pour les évaluer dans une base Supabase de développement jetable :

1. `draft_category_stock_schema.sql` — stock global par catégorie et mouvements ;
2. `draft_checkout_manual_payment_schema.sql` — commandes, lignes et factures ;
3. `draft_post_arrival_category_stock.sql` — réception des ballons/fournisseurs ;
4. `draft_create_approve_manual_checkout_order.sql` — création et approbation propriétaire ;
5. `draft_confirm_manual_checkout_payment.sql` — confirmation manuelle du paiement reçu ;
6. `draft_public_order_channels.sql` — liens permanents QR/réseaux, dépôt anonyme limité, file propriétaire.

**Les six scripts ont été exécutés sur PostgreSQL 17 temporaire dans GitHub Actions.**
Ce n'est pas une qualification de déploiement Supabase. Les points ci-dessous restent bloquants
avant utilisation réelle :

- vérifier la syntaxe et les contraintes PostgreSQL via une vraie exécution sur base isolée ;
- auditer les privilèges de `SECURITY DEFINER`, les RLS et l'accès de `anon` ;
- tester les transactions concurrentes, les doublons et la séparation TEST / RÉEL ;
- ne jamais interpréter le prénom saisi comme une preuve d'identité ;
- n'autoriser que le propriétaire, jusqu'à l'ajout de droits précis pour les caissiers ;
- vérifier le schéma des commandes publiques QR/social et limiter les abus avant leur ouverture ;
- ne pas brancher ces RPC au site de production avant la validation complète.

Tests statiques : `node tests/sql-draft-safety.mjs`.
Tests transactionnels sur base jetable : `bash tests/run-postgres-checkout.sh`
(uniquement avec `PGDATABASE=covi_ci` et `PGHOST=127.0.0.1`).
Ces tests inspectent **statiquement** les brouillons ; ils ne prouvent pas la validité des transactions ni la sécurité effective de la base.

Voir `docs/manual-checkout-isolated-validation.md` et `docs/caisse-validation-manuelle-v1.md`.

Les liens publics sont **désactivés tant que le propriétaire ne les active pas**.
Ils ne donnent jamais accès à la validation du paiement. Le dépôt public est limité
dans PostgreSQL à 60 demandes/minute et 1 000/jour par boutique, mais un filtrage
complémentaire à l'entrée du service sera requis avant ouverture réelle.
