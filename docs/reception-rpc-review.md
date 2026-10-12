# COVI — Revue de la transaction de réception (brouillon)

Date : 12 octobre 2026. **Aucun test SQL exécuté ; aucun déploiement.**

Fichier : `supabase/migrations/draft_post_arrival_category_stock.sql`.

## Comportement visé
- Réception d'un arrivage existant `received`, appartenant à une boutique de l'utilisateur authentifié.
- Quantités agrégées par catégorie, séparation `is_test`, journal d'entrée et mise à jour du stock dans une transaction.
- Verrouillage `FOR UPDATE` de l'arrivage pour sérialiser deux tentatives de réception.
- Refus d'une seconde réception avec un autre identifiant d'opération.

## Points bloquants avant application
1. **Idempotence : correctif écrit, non testé**. Le brouillon enregistre maintenant les lignes regroupées dans `arrival_stock_postings` ; une répétition identique retourne le nombre de catégories, tandis qu'un même identifiant avec un contenu différent doit échouer. Vérifier réellement les cas réordonnés, doublonnés et concurrents.
2. **Privilèges `SECURITY DEFINER`** : créer une fonction possédée par un rôle dédié et limité ; vérifier que l'absence de politique d'écriture directe n'empêche pas l'exécution contrôlée.
3. **Traçabilité** : décider comment corriger une réception erronée sans effacer l'historique ; ne jamais écraser les entrées de journal.
4. **Réception de ballons multiples** : tester la concurrence sur une catégorie commune et la limite de l'entier PostgreSQL.
5. **Schéma du coût** : les frais globaux restent dans `arrivals`; aucune ventilation artificielle par article.
6. **Politique d'arrivage existant** : décider si l'enregistrement d'un arrivage ancien déjà reçu doit être permis explicitement ; ne pas importer les simulations par défaut.
7. **Tests de base jetable** : contrôler anonymes, autres boutiques, doublons, erreurs JSON, dépassements et retour arrière atomique.

## Séquence suivante
- La table `arrival_stock_postings` et la comparaison JSONB canonique ont été ajoutées au brouillon. Exécuter les tests en base jetable avant toute activation.
- Tester les cas en base isolée.
- Préparer ensuite une transaction de caisse séparée, sans changer `record_sale` ni l'authentification existantes.
