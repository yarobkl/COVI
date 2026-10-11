# Migration SaaS multi-boutiques — plan SQL de transition (NON EXÉCUTABLE EN PRODUCTION)

> **Important :** ce document décrit une migration future. Ne pas copier-coller en production sans tests PostgreSQL, revue RLS et accord explicite du propriétaire de COVI.

## Constat vérifié dans main

La migration `20261007065227_single_xaf_shop_onboarding.sql` crée l'index unique `shops_owner_id_uidx` sur `public.shops(owner_id)` et remplace `create_my_shop` par une fonction qui retourne la boutique existante en cas de conflit. Cela impose **une boutique par utilisateur** et contredit le modèle SaaS validé. Il faut changer les deux éléments ensemble, jamais supprimer l'index seul.

## Ordre des migrations futures

1. **Audit du schéma existant** : inspecter `shops`, politiques RLS, triggers, `create_my_shop`, fonctions de ventes/stock/arrivages, clés étrangères et scripts d'onboarding ; confirmer les politiques applicables aux employés.
2. **Créer les structures SaaS** sans toucher aux données : comptes Owner, plan tarifaire versionné, abonnements et quota, factures, paiements Mobile Money rapprochés, journal d'audit et invitations. Les champs sensibles sont protégés par RLS avec `REVOKE` des écritures directes aux clients.
3. **Rattacher les comptes existants** : pour chaque `shops.owner_id` déjà présent, créer un compte commercial lié à `auth.users` et un abonnement de transition explicitement identifié. **Ne pas inventer un paiement réel ou marquer payé un client historique.** La politique d'accès transitoire doit être validée avant déploiement.
4. **Créer une fonction serveur atomique** `create_my_shop` : authentification, compte Owner, abonnement actif, nombre de boutiques inférieur au quota ; verrouiller la ligne d'abonnement avec `FOR UPDATE` avant le comptage et l'insertion ; conserver la signature attendue par le frontend. Valider noms et devise XAF.
5. **Seulement ensuite** retirer `shops_owner_id_uidx` dans la même migration transactionnelle. Ne pas laisser un intervalle où les clients peuvent créer des boutiques sans contrôle du quota.
6. **Renforcer les écritures métier** : vérifier le droit de l'utilisateur sur la boutique et l'état de l'abonnement dans toutes les RPC et politiques concernées, notamment `record_sale` et `record_cart_sale` (branches en cours, à intégrer avant migration). Les requêtes de lecture peuvent rester accessibles pendant une suspension selon la politique décidée.
7. **Contrôler les permissions** : fonctions SECURITY DEFINER avec `search_path` fixé, permissions EXECUTE minimales, `auth.uid()` vérifié, `service_role` exclusivement côté serveur. Les opérations Super Admin (validation de paiement, quota, suspension) sont journalisées et ne sont jamais appelables avec de simples droits Owner.
8. **Préparer le déploiement** : sauvegarde, tests SQL/RLS sous plusieurs utilisateurs, préproduction, plan de retour arrière, puis autorisation explicite avant toute exécution sur Supabase de production.

## Exemple de logique transactionnelle (pseudo-SQL, pas une migration prête à appliquer)

```sql
-- Dans public.create_my_shop(...), après vérification de auth.uid() :
-- SELECT id, shop_limit FROM subscriptions
-- WHERE owner_account_id = v_owner_account_id
--   AND status = 'active' AND period_end > now()
-- FOR UPDATE;
-- Si aucune ligne : refuser.
-- SELECT count(*) FROM shops WHERE owner_id = auth.uid();
-- Si count >= shop_limit : refuser avec un code métier stable.
-- INSERT INTO shops(owner_id, name, city, country, currency)
-- VALUES (auth.uid(), v_name, v_city, v_country, 'XAF')
-- RETURNING *;
```

La requête doit se trouver **dans une seule transaction PostgreSQL**. Le verrou sur la ligne d'abonnement sérialise les créations simultanées du même Owner.

## Points d'intégration front-end

- Un seul domaine : routes `/login`, `/admin`, `/mes-boutiques`, `/boutiques/:shopId/...` ou équivalents compatibles avec le routeur actuel.
- Après login, charger la liste des boutiques accessibles, sans supposer une seule boutique.
- Conserver `shopId` dans les appels métier ; le serveur vérifie systématiquement les permissions.
- Prévoir une boutique active explicite et isoler le cache/les opérations hors connexion par utilisateur + boutique.
- Les écrans V1 existants ne doivent pas être remplacés avant que l'onboarding multi-boutiques soit testé de bout en bout.

## Tests de non-régression obligatoires

- Ancien Owner : sa boutique et ses données restent accessibles après migration.
- Owner actif quota 1 : deuxième boutique refusée.
- Owner actif quota 3 : trois boutiques possibles, quatrième refusée.
- Deux créations concurrentes lorsque quota 2 et une boutique existante : **une seule** création réussit.
- Owner sans abonnement ou suspendu : aucune création, aucune écriture métier.
- Owner A ne lit/écrit jamais dans boutique B, même avec `shop_id` forgé.
- Paiement non confirmé, montant incomplet ou référence dupliquée : aucun quota ajouté.
- Réduction de quota : pas de suppression de boutique ni de données.
- Une vente hors ligne rejouée après suspension ne contourne pas les contrôles.
- Un utilisateur standard ne peut pas modifier `subscriptions`, `subscription_payments` ni `platform_admins`.

## Décisions bloquantes avant implémentation

- Prorata lors de l'ajout d'une boutique en milieu de période.
- Période de grâce et droits de lecture/écriture durant cette période.
- Statut transitoire des comptes V1 existants lors de la mise en place de l'abonnement.
- Règles de réduction de quota, factures et remboursements.
