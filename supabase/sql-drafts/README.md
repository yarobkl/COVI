# SQL expérimental COVI — NE PAS APPLIQUER

Ces fichiers sont des **brouillons de conception**. Ils sont volontairement placés dans `supabase/sql-drafts/` et **non** dans `supabase/migrations/`.

Une commande standard de migration Supabase ne doit pas les appliquer. Ne jamais les déplacer dans `supabase/migrations/`, les utiliser dans `supabase db push` ni les exécuter sur le projet de production COVI sans avoir validé les tests et obtenu une autorisation explicite.

Ordre **prévisionnel** pour les évaluer dans une base Supabase de développement jetable :

1. `draft_category_stock_schema.sql` — stock global par catégorie et mouvements ;
2. `draft_checkout_manual_payment_schema.sql` — commandes, lignes et factures ;
3. `draft_post_arrival_category_stock.sql` — réception des ballons/fournisseurs ;
4. `draft_create_approve_manual_checkout_order.sql` — création et approbation propriétaire ;
5. `draft_confirm_manual_checkout_payment.sql` — confirmation manuelle du paiement reçu.

**Aucun de ces scripts n'est certifié exécutable.** Tous les points ci-dessous restent bloquants avant utilisation réelle :

- vérifier la syntaxe et les contraintes PostgreSQL via une vraie exécution sur base isolée ;
- auditer les privilèges de `SECURITY DEFINER`, les RLS et l'accès de `anon` ;
- tester les transactions concurrentes, les doublons et la séparation TEST / RÉEL ;
- ne jamais interpréter le prénom saisi comme une preuve d'identité ;
- n'autoriser que le propriétaire, jusqu'à l'ajout de droits précis pour les caissiers ;
- vérifier le schéma des commandes publiques QR/social et limiter les abus avant leur ouverture ;
- ne pas brancher ces RPC au site de production avant la validation complète.

Tests de sécurité préliminaires : `node tests/sql-draft-safety.mjs`.
Ces tests inspectent **statiquement** les brouillons ; ils ne prouvent pas la validité des transactions ni la sécurité effective de la base.

Voir `docs/manual-checkout-isolated-validation.md` et `docs/caisse-validation-manuelle-v1.md`.
