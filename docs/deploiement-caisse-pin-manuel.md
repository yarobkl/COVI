# COVI — Débloquer la migration des caissiers par PIN

## État vérifié le 14 octobre 2026

- Projet Supabase réel : `bmbwmwgfzrijglzcgjut` (eu-west-3, ACTIVE_HEALTHY).
- 150 ventes, 55 produits, 3 boutiques.
- 8 migrations précédentes de caisse déjà installées, **NE PAS LES REJOUER**.
- Migration `shared_cashier_profiles` non appliquée.
- Les tables `public.shop_cashier_profiles` et `public.shop_cashier_tills` sont absentes.
- CI GitHub [38621328358](https://github.com/yarobkl/COVI/actions/runs/38621328358) : test-web SUCCESS, test-db SUCCESS.
- La tentative d'application par le connecteur a été **bloquée par un contrôle de sécurité avant confirmation d'exécution**. Ne pas contourner ce refus par `execute_sql` ou une autre voie automatique.

## Source unique de vérité

Migration de production à installer **une fois** :

[`supabase/migrations/20261014210000_shared_cashier_profiles.sql`](https://github.com/yarobkl/COVI/blob/4be0420b5bca8f176d9badb3e0405af55937e5e4/supabase/migrations/20261014210000_shared_cashier_profiles.sql)

Commit GitHub contrôlé : `4be0420b5bca8f176d9badb3e0405af55937e5e4`. Ne jamais appliquer `docs/experimental/counter_session_rls_prototype.sql`.

## Reprise manuelle, si l'application autorisée via Supabase reste bloquée

1. Le propriétaire ouvre son [SQL Editor Supabase COVI](https://supabase.com/dashboard/project/bmbwmwgfzrijglzcgjut/sql) avec son compte autorisé.
2. Il ouvre le fichier SQL exact ci-dessus, le passe en revue et l'exécute **une seule fois**. Le fichier installe les profils PIN et leurs tables privées avec RLS, les RPC, l'attribution des ventes et le retour au responsable par PIN ; il ne supprime aucune vente.
3. Si une erreur SQL survient, **ne pas cliquer à nouveau** sans vérification de l'état. Transmettre le message intégral et la ligne fautive.
4. Vérifier en lecture seule, dans le SQL Editor :

```sql
SELECT
  to_regclass('public.shop_cashier_profiles') IS NOT NULL AS profils_presents,
  to_regclass('public.shop_cashier_tills') IS NOT NULL AS caisses_presentes,
  (SELECT count(*) FROM public.sales) AS ventes,
  (SELECT count(*) FROM public.products) AS produits,
  (SELECT count(*) FROM public.shops) AS boutiques;

SELECT
  proname,
  has_function_privilege('authenticated', oid, 'EXECUTE') AS autorise_auth
FROM pg_proc
WHERE pronamespace='public'::regnamespace
  AND proname IN (
    'list_shared_cashiers',
    'create_shared_cashier',
    'open_shared_cashier_till',
    'unlock_shared_cashier_till',
    'close_shared_cashier_till'
  );
```

5. L'exécution SQL dans l'éditeur peut ne **pas** enregistrer une entrée dans `supabase_migrations.schema_migrations`. Ne pas considérer la migration non exécutée si les tables et fonctions sont déjà présentes. Vérifier d'abord l'état réel puis réconcilier proprement l'historique de migration avant tout futur déploiement automatisé.
6. Après installation vérifiée, déployer le **front exact** depuis la branche `claude/caisse-multi-caissiers` seulement si tests GitHub verts sur le commit ciblé et validation du propriétaire. Ne pas fusionner automatiquement dans `main`.
7. Tests humains en boutique : créer un caissier avec un PIN, ouvrir sa caisse, changer de caissier par second PIN, vendre uniquement dans un environnement d'essai, contrôle de remise et de stock, retour au responsable par PIN. Le compte de gestion est partagé **par choix métier** ; le PIN protège l'accès à une vente attribuée au caissier, **pas** toutes les fonctions de gestion accessibles à un utilisateur de ce compte.

## En cas de blocage du connecteur

L'agent doit déclarer explicitement l'échec du connecteur, conserver l'existant, et demander à un administrateur autorisé d'utiliser le SQL Editor, plutôt que d'exécuter la même DDL via un canal détourné.
