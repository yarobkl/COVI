# COVI — Registre partagé des anomalies métier (GPT)
Dernière revue : 24 octobre 2026. **Seules les observations contrôlées en code sont qualifiées ; les cas non exécutés sont signalés à part.** Claude conserve la propriété des corrections techniques.

| Réf. | Priorité | Domaine | Constats et reproduction | Responsable technique | Décision / statut |
| --- | --- | --- | --- | --- | --- |
| ANO-FIN-001 | P0 | Salon / rapports | Voir `salon_report` (PR #64) : facturer 12 000 FCFA le 28 septembre, rembourser le 5 octobre, puis consulter le rapport de septembre et celui d'octobre. La clause `l.refunded_at is null` supprime potentiellement la vente du CA de septembre rétrospectivement. Le rapport d'octobre enregistre le décaissement mais ne rattache pas explicitement l'ajustement de CA à octobre. | CLA-05 (règle), CLA-02 (SQL/migration) | **Décision propriétaire requise** sur FIN-004 ; test réel non exécuté |
| ANO-QA-001 | P0 | Préproduction / accès | Le connecteur ChatGPT ne voit pas `stcsjwxmmxnjwisqkudz` : refus d'autorisation, puis `link_id must identify an eligible linked account`. La présence réelle des migrations est inconnue côté GPT. | CLA-02 fournit des preuves, aucune modification de connexion requise pour poursuivre | **Limitation d'observation**, pas un défaut prouvé dans Supabase |
| ANO-UX-001 | P1 | Salon / hors ligne | Simuler paiement reçu par le serveur mais réponse perdue au client ; le texte générique de `salonErrorMessage` annonce « rien n'a été enregistré ». Vérifier affichage de l'état réel et réutilisation de la même clé d'opération avant une nouvelle tentative. | CLA-05 / CLA-07 | **Risque à reproduire**, correction non présumée nécessaire sans preuve |

## Anomalies historiques vérifiées comme corrigées en code
- `SalonCheckoutPage.tsx` : `onChanged={data.reload}` présent sur la branche PR #64 ; exécution E2E restant à valider.
- `SalonReportsPage.tsx` : fuseau `time_zone` chargé depuis `salonApi.settings` ; tests multizones restant à valider.

Pour clôturer un ticket : joindre une preuve reproductible (version, référence du scénario, attente/observation, résultat serveur), faire corriger par Claude, puis obtenir une contre-vérification GPT-06.

## Nouveaux constats sur `integration/preprod`

| Réf. | Priorité | Domaine | Constats et reproduction | Responsable technique | Décision / statut |
| --- | --- | --- | --- | --- | --- |
| ANO-PRE-001 | P0 | Seed Boutique | `seed_retail_restaurant.sql` insère `status='available'` alors que COVI sélectionne `status='active'`. Confirmer contrainte, relancer seed uniquement sur la cible de test. | CLA-02 / CLA-03 | **Issue #68, non exécuté à distance** |
| ANO-PRE-002 | P0 | Auth de test | `insert into auth.users(id)` crée des UUID de propriétaires sans compte email connecté ; création séparée d'un utilisateur peut fournir un autre UUID. Faire un login réel puis vérifier l'accès propriétaire aux 3 établissements. | CLA-02 | **Issue #68, à confirmer** |
| ANO-PRE-003 | P0 | Isolation environnement | Le client Vite contient une URL de production de repli si `VITE_SUPABASE_URL` manque. Prouver la cible réelle de l'aperçu Vercel avant toute écriture ; jamais de fallback silencieux sur production. | CLA-07 / CLA-02 | **Issue #68, prévention impérative** |
| ANO-PRE-004 | P1 | Recette RLS | Le script de vérification teste les privilèges directs mais pas encore l'ensemble des RPC multi-tenant en session A/B. Ajouter preuve de tests négatifs avant GO. | CLA-02 | **Lacune de couverture, non fuite avérée** |

Oracle calculé : `docs/recette/JEU-DONNEES-PREPROD.md`. L'issue [#68](https://github.com/yarobkl/COVI/issues/68) centralise les corrections techniques attendues de Claude.
