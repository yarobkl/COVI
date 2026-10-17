# COVI — Revue de sécurité des ventes et du stock (12 octobre 2026)

**Statut : revue en lecture seule. Aucun changement appliqué à Supabase.**

## Constat vérifié

- `public.record_sale` est une fonction `SECURITY INVOKER` (prosecdef=false), propriétaire `postgres`.
- La fonction est exécutable par `PUBLIC`, `anon`, `authenticated` et `service_role` selon ses ACL.
- Elle vérifie quantité positive, prix non négatif, moyen de paiement autorisé, identifiant d'opération obligatoire, existence d'une vente antérieure de même opération, disponibilité du produit, quantité en stock ; elle verrouille le produit `FOR UPDATE` et crée vente/ligne puis décrémente le produit.
- **Elle ne contient pas de contrôle explicite `auth.uid()`** ; les politiques RLS des tables existantes vérifient en revanche que le propriétaire de la boutique est l'utilisateur authentifié. Il faut donc vérifier les effets effectifs des privilèges d'exécution et RLS avant toute conclusion d'exploitabilité.
- Toutes les six tables publiques ont des politiques `ALL` pour `authenticated` limitées au propriétaire de boutique. Aucune politique anonyme listée pour ces tables.

## Risques à tester et actions recommandées

1. Vérifier avec un utilisateur anonyme que `record_sale` échoue et ne crée aucune vente.
2. Vérifier avec un compte authentifié de la boutique A qu'il ne peut pas vendre un produit de la boutique B, même en falsifiant les paramètres.
3. Tester les replays de `client_operation_id` avec paramètres différents : la fonction renvoie la vente existante sans revérifier le contenu. Définir la politique d'idempotence et de détection de conflit pour la nouvelle caisse.
4. Vérifier les droits de modification directe des tables `sales`, `sale_items`, `products` : la politique `ALL` du propriétaire permet potentiellement des écritures directes qui contournent les invariants de la RPC. Prévoir des privilèges restreints ou des RPC dédiées avant activation du stock central.
5. Éviter une correction de production précipitée de `record_sale` : son exécution dépend des droits actuels et de la file hors connexion.
6. Le nouveau stock central doit être modifié uniquement via RPC serveur avec contrôle explicite `auth.uid()`, verrouillage des lignes, contraintes de stock non négatif, opérations idempotentes et journal immuable.
7. Ajouter des contraintes de cohérence boutique : `arrival_category_items.shop_id` doit correspondre à `arrivals.shop_id`, et `stock_movements.shop_id` aux ventes/arrivages associés. Les clés étrangères actuelles du brouillon ne suffisent pas à prouver cette cohérence.
8. Ne pas créer de politiques publiques pour les tables de stock ; pour les commandes QR/lien, utiliser des fonctions minimales, anti-abus et des jetons opaques.

## Données de simulation

Une requête agrégée sur `products` a retourné : 6 produits actifs `is_test=true`, stock cumulé 9 ; 48 produits vendus `is_test=true`, stock 0. Aucun produit non-test retourné. Ne pas convertir ces neuf unités en stock commercial réel.

## Décision de livraison

**Aucune migration SQL ni modification de droits sur la production** à ce stade. La prochaine étape est un test de sécurité en environnement isolé et la correction des lacunes du brouillon SQL avant validation.
