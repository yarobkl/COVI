# COVI — Revue de la transaction de réception (brouillon)

Date : 12 octobre 2026. **Aucun test SQL exécuté ; aucun déploiement.**

Fichier : `supabase/migrations/draft_post_arrival_category_stock.sql`.

## Comportement visé
- Réception d'un arrivage existant `received`, appartenant à une boutique de l'utilisateur authentifié.
- Quantités agrégées par catégorie, séparation `is_test`, journal d'entrée et mise à jour du stock dans une transaction.
- Verrouillage `FOR UPDATE` de l'arrivage pour sérialiser deux tentatives de réception.
- Refus d'une seconde réception avec un autre identifiant d'opération.

## Points bloquants avant application
1. **Idempotence incomplète** : une répétition avec le même `operation_id` mais un contenu différent renvoie actuellement 0 ; il faut enregistrer une empreinte canonique des lignes et rejeter le conflit.
2. **Privilèges `SECURITY DEFINER`** : créer une fonction possédée par un rôle dédié et limité ; vérifier que l'absence de politique d'écriture directe n'empêche pas l'exécution contrôlée.
3. **Traçabilité** : décider comment corriger une réception erronée sans effacer l'historique ; ne jamais écraser les entrées de journal.
4. **Réception de ballons multiples** : tester la concurrence sur une catégorie commune et la limite de l'entier PostgreSQL.
5. **Schéma du coût** : les frais globaux restent dans `arrivals`; aucune ventilation artificielle par article.
6. **Politique d'arrivage existant** : décider si l'enregistrement d'un arrivage ancien déjà reçu doit être permis explicitement ; ne pas importer les simulations par défaut.
7. **Tests de base jetable** : contrôler anonymes, autres boutiques, doublons, erreurs JSON, dépassements et retour arrière atomique.

## Séquence suivante
- Ajouter une table de journal d'opérations avec hash du payload ou une contrainte équivalente.
- Tester les cas en base isolée.
- Préparer ensuite une transaction de caisse séparée, sans changer `record_sale` ni l'authentification existantes.
