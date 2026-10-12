# COVI — Audit de sécurité pré-intégration (12 octobre 2026)

**Verdict : NO-GO pour fusion vers `main`, migration Supabase ou activation du nouveau checkout en production.**

Audit réalisé **sans écriture** sur la base Supabase COVI et sans modification de l’authentification existante. La seule modification de code au cours de cet audit concerne un test de permissions PostgreSQL supplémentaire, exécuté dans une base jetable GitHub.

## Périmètre

Branche : `feature/covi-stock-central-omnichannel`, pull request brouillon #22.
Audit du parcours panier par catégorie → commande manuelle/QR/social → approbation → confirmation humaine des espèces/Mobile Money → reçu avec prénom → mouvement de stock et historique de vente.
Contrôles des droits SQL, des fonctions `SECURITY DEFINER`, de l’isolation des boutiques, du stock de test, de la protection des informations client et de l’exposition publique.

## Contrôles satisfaisants (portée limitée aux tests)

1. La nouvelle caisse est protégée par `VITE_COVI_CATEGORY_CHECKOUT_ENABLED === 'true'`, **désactivé par défaut**.
2. Les nouvelles migrations sont conservées dans `supabase/sql-drafts/`, à l’écart des migrations automatiquement appliquées. Aucune nouvelle table de caisse n’a été détectée dans la base COVI actuelle.
3. Les RPC d’approbation et de confirmation vérifient `auth.uid()` et `shops.owner_id` ; un prénom saisi seul n’accorde aucun droit.
4. Les tests précédents sur PostgreSQL 17 temporaire ont vérifié : concurrentes sur dernier article, idempotence de double-clic, refus sans rôle, refus interboutiques, stock TEST/réel séparé, rollback intégral si stock insuffisant et validation humaine avant déduction.
5. Le catalogue public ne retourne que les noms et identifiants des catégories ; la file privée des clients vérifie l’appartenance de la boutique. Les liens peuvent être désactivés ou renouvelés.
6. Le QR est généré localement, sans transmettre le jeton à un serveur tiers de création de QR.
7. Dernier état GitHub précédent à cet audit : jobs `COVI Windows` et `COVI isolated branch checks` réussis. Le nouveau test de permission est à vérifier indépendamment.

Ces contrôles ne constituent **pas** un audit d’une instance Supabase Auth/PostgREST hébergée réelle, ni un test d’intrusion.

## Points bloquants

| Priorité | Constat fondé | Risque / exigence avant activation |
| --- | --- | --- |
| **B1 — élevé** | `public.submit_checkout_public_order` est appelable directement via RPC anonyme avec un jeton de boutique ; les quotas SQL sont **globaux à la boutique** (60/minute, 1 000/jour), sans quota par source. `get_checkout_public_catalog` n’a pas de quota. | Un acteur qui possède un lien public peut saturer les quotas de la boutique et empêcher les commandes légitimes, ou multiplier les lectures. **Installer une protection côté serveur à l’entrée (Edge Function/gateway, limitation IP ou par session, anti-bot, supervision), puis supprimer le chemin d’écriture anonyme direct qui contournerait cette protection.** Une règle WAF sur la seule page Vercel ne sécurise pas un appel direct à Supabase. |
| **B2 — élevé** | Les droits réels de la base COVI actuelle autorisent le rôle `authenticated` à `UPDATE`/`DELETE` `public.sales`, et à `UPDATE` `public.sale_items`. Les RLS actuelles limitent ces actions aux enregistrements de sa boutique, **mais n’imposent pas une comptabilité immuable**. | Une vente de la nouvelle caisse pourrait être modifiée dans le registre historique sans modifier son reçu figé. **Prévoir une politique d’intégrité des écritures financières, une piste d’audit et des corrections par opérations compensatrices, sans casser la caisse actuelle.** Ne surtout pas révoquer les droits de l’existant en production sans étude de compatibilité. |
| **B3 — élevé** | Les nouvelles fonctions `SECURITY DEFINER` et les règles RLS ont été testées dans une fixture PostgreSQL avec un substitut de `auth.uid()`, pas avec le PostgREST et les rôles Supabase réels. | Tester le comportement des rôles `anon`, `authenticated`, `service_role` et du propriétaire des fonctions, y compris privilèges hérités, accès interboutiques, exécution API et refus de mutations directes, dans une instance isolée équivalente à Supabase. |
| **B4 — élevé** | L’historique historique `HistoryPage` transforme chaque vente en `sale_items` produit individuel, alors que la caisse catégorie n’insère **aucune** ligne `sale_items`. Le tableau de bord récent fait également cette jointure. | Les nouvelles ventes risquent d’être visibles dans les totaux mais **absentes du détail des ventes et des statistiques par article/catégorie**. Corriger lecture, rapprochement et rapport avant fusion. |
| **B5 — métier/sécurité** | L’encaissement est **réservé au propriétaire** actuellement. Le prénom est déclaré au moment du paiement ; il ne prouve pas l’identité d’un caissier disposant d’un autre compte. | Si des employés doivent encaisser, créer des comptes personnels avec rôle boutique, permissions et traçabilité de chaque confirmation. Ne jamais partager le compte du propriétaire pour contourner cette restriction. |
| **B6 — produit** | Le vendeur peut accepter le montant d’une commande publique, mais pas le rectifier ou le refuser en conservant une trace ; les commandes en attente ne disposent pas d’un cycle de refus/expiration opérationnel. | Ajouter une validation explicite du montant négocié, possibilité de refus/correction, expiration et suivi cohérent sans débit prématuré de stock. |

## Autres observations

- **Supabase Auth :** l’advisor du projet COVI signale `Leaked Password Protection Disabled`. Documentation : https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . Il faut examiner les options disponibles sur le plan actuel avant d’intervenir ; ne pas altérer Google/Facebook sans autorisation.
- **Vie privée :** téléphone et notes des commandes sont conservés sans durée de rétention ni mécanisme d’archivage/suppression documentés. Fixer une politique de conservation et minimiser les données du client.
- **Tests non réalisés :** smartphone physique, accessibilité, vraie connexion Supabase, attaque abusive sur les endpoints publics, migrations sur une copie équivalente de la production, reprise en cas de coupure complète.
- **Contrat visuel :** la DA « Le Cahier » est conservée dans les nouveaux composants. Cela ne dispense pas de vrais tests tactiles et d’impression.

## Conditions explicites pour le GO

1. Corriger les six blocages ci-dessus selon le périmètre réel de la V1 (pour une V1 sans employés, les employés restent **inaccessibles**, jamais simulés par un prénom).
2. Faire réussir les tests de permissions SQL et d’isolation, plus les suites TypeScript, lint, build, format et PostgreSQL.
3. Valider l’intégrité `sales` / `checkout_order_lines` / `manual_payment_confirmations` et le rapprochement des statistiques.
4. Vérifier en environnement isolé le fonctionnement réel des JWT Supabase et de la protection des endpoints publics.
5. Effectuer une recette tactile sur smartphone et une recette de facture, sans utiliser de transaction Mobile Money réelle pour les tests.
6. Préparer une migration additive réversible et un plan de retour arrière, avec drapeau désactivé par défaut et vérification après déploiement.
7. Obtenir une **autorisation explicite** avant toute fusion, changement d’authentification, migration ou mise en production.

## Traçabilité

- PR de travail : https://github.com/yarobkl/COVI/pull/22
- Scénarios SQL : `tests/postgres/`
- Tests de permissions ajoutés : `tests/postgres/pre-integration-security-audit.sql`
- Scripts brouillons protégés : `supabase/sql-drafts/`

**État final : audit documenté, production COVI et autres projets intacts. Tant qu’un point B1–B4 n’est pas résolu, le verdict reste NO-GO.**
