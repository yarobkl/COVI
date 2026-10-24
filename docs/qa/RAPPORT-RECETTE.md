# COVI — Rapport indépendant de recette et de risques (GPT-06)
Date : 24 octobre 2026. **Audit statique GitHub seulement** ; aucun test d'écriture ni migration exécuté par ChatGPT.

## Statut général
**NO-GO provisoire pour la production** tant que la préproduction, les tests E2E et la règle financière FIN-004 ne sont pas vérifiés. Cela ne signifie **pas** que Claude a échoué : cela distingue preuves inspectées et preuves encore attendues.

## Sources consultées
- PR #64 : `feature/covi-salon-professional-v1`, commit `c85d7a378bcb049265ce6b56bab2ac2449d20c2f` au moment de la revue.
- PR #66 : `feature/covi-refonte-wave`, commit `fc8ccc193959d28dfc486f9f65989710d374507e` au moment de la revue.
- `src/features/salon/SalonCheckoutPage.tsx` : après modification de ticket, `onChanged={data.reload}` actualise les listes/totaux.
- `src/features/salon/SalonReportsPage.tsx` : charge `salonApi.settings(shopId).settings.time_zone` et calcule la période dans le fuseau du salon.
- `supabase/migrations/20261024095000_salon_pro_reports.sql` : filtre les lignes remboursées dans le CA de la date de vente mais date les décaissements à `recorded_at`.
- `supabase/migrations/20261024093000_salon_pro_cash_stock.sql` : les remboursements sont enregistrés dans `salon_payments` et les lignes portent `refunded_at`.
- PR #67 : nos référentiels de scénarios et calculs attendus.

## Observations
| ID | Statut | Criticité | Observation / suite |
| --- | --- | --- | --- |
| QA-OBS-001 | **Non confirmé** | P0 | Cible Supabase `stcsjwxmmxnjwisqkudz` : le connecteur ChatGPT a refusé l'accès, puis signalé `link_id must identify an eligible linked account`. Aucune conclusion sur l'état réel de la base. CLA-02 doit fournir la liste des migrations + la preuve du Reference ID cible |
| QA-OBS-002 | **À arbitrer** | P0 | FIN-004 : remboursement effectué dans un mois ultérieur au paiement ; possible recalcul rétrospectif du CA d'origine, incompatible avec une clôture figée sauf méthodologie explicitée. Voir `docs/recette/FINANCE.md` |
| QA-OBS-003 | **Correctif présent dans le code** | P1 | `SalonCheckoutPage` appelle maintenant `data.reload` après édition. **Validation en préproduction à obtenir**, sans réintroduire l'ancien défaut |
| QA-OBS-004 | **Correctif présent dans le code** | P1 | `SalonReportsPage` utilise le fuseau propre au salon. **Validation avec plusieurs fuseaux et passages de journée à obtenir** |
| QA-OBS-005 | **À exécuter** | P0 | PR #64 + PR #66 sur branche `integration/preprod` : aucun résultat E2E Supabase utilisable par GPT-06, malgré les tests locaux annoncés et les contrôles visuels |
| QA-OBS-006 | **À exécuter** | P0 | RLS : prouver l'impossibilité pour le compte B de lire, modifier ou encaisser les données de A, y compris via RPC privilégiées |
| QA-OBS-007 | **À exécuter** | P1 | Étudier une rupture réseau après écriture serveur confirmée mais avant réponse client : l'erreur frontend `salonErrorMessage` dit parfois « rien n'a été enregistré ». Vérifier récupération par clé/idempotence et éviter les consignes ambiguës au caissier |
| QA-OBS-008 | **À confirmer** | P1 | L'échec Cloudflare signalé comme antérieur à la refonte doit être isolé, classé par impact et documenté par CLA-07 |

## Décisions et preuves manquantes
1. **Propriétaire** : valider la règle de clôture et remboursement FIN-004.
2. **CLA-02** : fournir la cible effective, l'historique ordonné des migrations et les tests négatifs de RLS.
3. **CLA-03/04/05** : exécuter les scénarios RET/RES/SAL/FIN avec états de base avant/après.
4. **CLA-06** : fournir les captures du Salon intégré avec données de préproduction, et les résultats 390/1280 px.
5. **CLA-07** : fournir les exécutions versionnées de CI/E2E, les limitations et la stratégie de retour arrière.
6. **GPT-06** : comparer ces preuves aux attendus et changer chaque ligne en PASS/FAIL/BLOQUÉ ; ne pas cocher une ligne sur la base d'une simple annonce.

## Garde-fous
Projet de test autorisé : `stcsjwxmmxnjwisqkudz`. Production interdite : `bmbwmwgfzrijglzcgjut`. Aucune opération d'écriture via GPT. Toute preuve présentée doit masquer clés, tokens et données réelles.

## Revue complémentaire — scripts de préproduction (24 octobre 2026)

- **Branche désormais visible :** `integration/preprod` (comparaison GitHub : 30 commits d'avance sur `main`, aucun commit en retard à l'instant de la revue). Les scripts `supabase/preprod/README.md`, `seed_retail_restaurant.sql`, `seed_salon.sql` et `verify_preprod.sql` sont présents sur cette branche ; leur présence n'établit **pas** leur application sur le projet distant.
- **QA-OBS-009 — P0, source vérifiée :** le seed Retail utilise `status='available'` pour les 5 produits, alors que `src/lib/types.ts` définit `active|sold|archived` et `src/lib/covi.ts` ne liste que `active`. Risque d'échec de contrainte ou d'article invisible. **Issue #68** pour CLA-02/CLA-03.
- **QA-OBS-010 — P0, test d'accès nécessaire :** les propriétaires d'exemple sont créés par `insert into auth.users(id)` sans véritables identifiants. Vérifier en login réel que les sessions Auth correspondent aux `owner_id` des 3 établissements ; ne pas présumer que des comptes créés plus tard héritent des UUID. **Issue #68**.
- **QA-OBS-011 — P0, sécurité :** `src/lib/supabase.ts` dispose d'une URL et d'une clé publique de production en valeurs de repli. Le README préproduction mentionne déjà ce danger. Ne lancer aucun E2E d'écriture avant preuve que la **version réellement chargée par le navigateur** utilise `stcsjwxmmxnjwisqkudz`. **Issue #68**.
- **QA-OBS-012 — P1, couverture de sécurité :** `verify_preprod.sql` examine notamment RLS et privilèges directs mais ne suffit pas, seul, à prouver l'isolation des fonctions RPC `SECURITY DEFINER` sous des sessions authentifiées A/B. CLA-02 doit joindre ces tests négatifs, avec statut serveur, sans secret.
- **Oracle indépendant :** `docs/recette/JEU-DONNEES-PREPROD.md`. Attendus cumulés sous réserve d'un seed complet : Boutique 51 000 XAF sur 2 ventes ; Salon 92 000 XAF sur 6 notes, 20 500 XAF de commissions dues et résultat de pilotage estimé −44 600 XAF. **Non exécuté** : ces valeurs sont des calculs à valider en base.

Aucune modification de SQL, des branches de Claude ou de la production n'a été effectuée par GPT.
