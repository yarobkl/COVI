# COVI — plan d'évolution sécurisé (22 octobre 2026)

> **Document de cadrage, sans changement applicatif.** Branche dédiée issue du commit `81318c3` de `main`. Aucune migration, aucun secret, aucun déploiement, aucune modification de configuration de production.

## 1. Objectif et garde-fous

Faire évoluer le système d'exploitation des PME en conservant l'existant : caisse, arrivages, ballons, stock, historique, tableaux de bord, fonctionnement hors ligne, QR clients, restaurant, salon, COVI Connect, Gemini, Tauri et le design **Le Cahier**.

**Invariants non négociables**
- Les écritures de ventes, stock et remboursements passent par les fonctions métier serveur existantes ; aucune écriture directe pour les contourner.
- Les droits sont vérifiés **dans PostgreSQL / Edge** ; aucun `shop_id`, code caissier, jeton public ou paramètre côté navigateur ne constitue une autorisation.
- Toute opération externe est idempotente et traçable. Les scénarios hors connexion restent sans doublon.
- Argent : distinguer CA, encaissement, coût des marchandises vendues, charges, marge, résultat de pilotage et trésorerie. Aucune approximation présentée comme bénéfice comptable officiel.
- Aucun module ajouté ne doit toucher aux données d'autres boutiques. Isoler les secteurs commerce, restaurant et salon.
- Pas de réécriture ERP, pas de remplacement du routeur hash sans besoin prouvé, pas de refonte graphique.
- Aucune migration appliquée directement en production ; chemin de retour arrière documenté avant toute activation.

## 2. État constaté (lecture du dépôt)

- Front : React 19 / TypeScript / Vite 8, `src/app/`, `src/features/`, `src/lib/` ; styles Le Cahier.
- Back : Supabase Auth, PostgreSQL + RLS, Storage, Edge Functions ; Tauri et Vercel.
- `src/app/routes.ts` : commerce + pages restaurant et salon + assistant.
- `src/lib/covi.ts` : `record_sale` en RPC, inventaire et file hors ligne.
- `src/lib/operations.ts` : arrivages, charges, agrégats d'écran.
- `supabase/config.toml` : passerelles publiques et privées (vérifier les contrôles internes de chaque handler).
- `.github/workflows/windows.yml` : format, lint, typecheck, build, tests JS, SQL PostgreSQL 16.
- PR #52 à #58 fusionnées, notamment restaurant, stock API, sites marchands et Gemini ; **ne pas réimplémenter** ces briques.
- Branches existantes de travail : `feature/api-stock-realtime-20261019`, `feature/covi-connect-websites-20261019`, `feature/covi-geo-intelligence-foundation`, `chatgpt/saas-subscription-architecture`, `feature/covi-restaurant-salon-v1`, etc. Leur présence ne prouve ni utilité ni absence de fusion : comparer leurs HEAD avec `main`.

**Limites du constat** : état de production Supabase/Vercel, résultats CI actuels, divergences de toutes les branches et licences exactes des dépendances tierces restent à vérifier avant décision de fusion.

## 3. Ordre d'exécution

### P0 — Fiabilisation sans nouveauté

1. Inventorier `main`, branches non fusionnées, migrations et contrats RPC (signatures, rôles, grants, RLS, search_path).
2. Comparer les branches potentiellement redondantes aux PR déjà fusionnées.
3. Exécuter sur clone éphémère : `npm ci`, `npm run format:check`, `npm run lint`, `npm run typecheck`, `npm run build`, `npm test`, `bash tests/sql/run.sh`.
4. Tester deux boutiques isolées, deux caissiers concurrents, commandes publiques, annulation/remboursement, synchronisation hors ligne, retour d'une commande en échec.
5. Identifier les divergences d'agrégats temporels entre JavaScript local et SQL `Africa/Brazzaville`; travailler sur des cas de test avant tout correctif.
6. Vérifier que toutes les Edge Functions avec `verify_jwt=false` ont un schéma de sécurité explicite : challenge, signature/secret, quotas, replay, contrôle d'origine selon le cas et validations serveur. Le JWT désactivé n'est pas en soi une vulnérabilité démontrée.

**Livrable P0** : tableau de couverture, défauts reproductibles et checklist de non-régression. Aucun déploiement.

### P1 — CRM natif minimal, indépendant du moteur de vente

Concevoir **dans COVI**, pas en copiant Twenty CRM :
- `crm_contacts` : `id`, `shop_id`, `display_name`, `kind` (client / fournisseur), téléphone normalisé optionnel, email optionnel, consentement marketing explicite et horodaté, `created_at`, `updated_at`.
- `crm_contact_notes` : notes rattachées à `shop_id`, `contact_id`, auteur, date ; limiter les informations personnelles et les droits de consultation.
- Liaison **optionnelle** ventes -> contact, sans exiger un compte client ni casser les ventes historiques ou hors ligne.
- Interfaces: annuaire, fiche, historique limité aux commandes **réellement associées**, recherche, suppression/anonymisation selon règles de conservation.
- Index par `shop_id` et colonnes de recherche ; contraintes FK composites inter-boutiques ou triggers, RLS sous `auth.uid()` ; vérifier permissions d'équipe.
- Migration additive uniquement, avec `IF NOT EXISTS` lorsque sûr, tests SQL sur deux boutiques et droits `anon`, et réconciliation des types TS générés.
- **Pas de** campagne marketing automatique sans consentement, ni fusion silencieuse des personnes sur simple numéro partagé.

**Critères d'acceptation** : tout achat fonctionne sans CRM ; aucune donnée CRM lisible entre boutiques ; création/modification depuis un rôle non autorisé refusée ; aucun impact sur les totaux et synchronisations.

### P2 — Automatisations

Commencer par Supabase Cron + Edge Functions + table d'outbox ou jobs idempotents ; mesurer le besoin avant d'ajouter Trigger.dev.
- Cas V1 : stock faible, commandes reçues, rapport hebdomadaire propriétaire.
- `automation_events` : `shop_id`, type, événement métier idempotent, statut, tentatives, timestamps, motif d'échec ; politique de rétention et RLS.
- Pas d'accès service-role dans React ; quotas par boutique, traitement robuste aux duplications et pannes, préférence de notification.
- Vérifier coûts et quotas ; ne jamais permettre à un commerçant de lancer des jobs pour une autre boutique.

### P3 — Gemini enrichi sans changer son socle

Étendre le handler `supabase/functions/covi-assistant`, les RPC **read-only** et `src/features/assistant/AssistantPage.tsx`.
- Réponses fondées sur des agrégats SQL autorisés, période et devise explicites.
- Toujours séparer conseils généraux des statistiques réellement disponibles ; exclure les tests et les écritures non synchronisées.
- Conserver garde propriétaire/caissier, consentement, limitation de débit et cloisonnement par boutique.
- Prompt injection : traiter les contenus métier comme données non fiables ; aucune action de vente, remboursement ou stock sur simple sortie LLM.
- Tests : boutique A/B, caissier partagé, historiques malveillants, limites de contexte, période vide, indisponibilité API.

### P4 — Commerce multicanal

Étendre `covi-connect` existant plutôt que démarrer un second backend Medusa :
- Catalogue paginé, disponibilités sans réservation implicite, import de commandes idempotent, états serveur contrôlés.
- Chaque commande importée exige validation métier avant éventuelle décrémentation de stock.
- Authentification des sites, rotation/révocation de clés, quotas et journalisation sans exposer les clés.

## 4. Analyse open source — intégrer seulement si utile

| Dépôt | Usage proposé | Mode | Décision provisoire |
| --- | --- | --- | --- |
| `triggerdotdev/trigger.dev` | traitements asynchrones durables | service indépendant | **différer** tant que Cron/Edge suffit ; vérifier licence/version et coûts |
| `twentyhq/twenty` | parcours CRM, champs et pipeline | inspiration ou API | **ne pas copier le cœur** sans vérification des obligations AGPL et du modèle commercial |
| `medusajs/medusa` | conception catalogue/commandes | architecture / modules spécifiques | **ne pas importer l'ERP entier** ; éviter double source de vérité stock et caisse |
| `langgenius/dify` | orchestration d'agents IA | référence | **ne pas intégrer** : Gemini sécurisé est déjà présent ; vérifier la licence avant éventuel usage futur |
| `n8n-io/n8n` | workflows administrés | service interne éventuel | **non prioritaire** ; vérifier restrictions licence pour une offre SaaS aux tiers |

Avant tout ajout, documenter commit/tag figé, licence et obligations, maintenance, CVE, bundle size, secret handling, données personnelles, coût d'hébergement, plan de sortie et tests. Une dépendance n'est pas approuvée parce qu'elle est « open source ».

## 5. Matrice de tests de non-régression

| Scénario | Attendu |
| --- | --- |
| Deux boutiques A/B | ni lecture ni écriture croisées |
| Deux ventes simultanées dernier article | une seule vente réussit ; stock >= 0 |
| Rejeu du même identifiant client hors ligne | une seule vente enregistrée |
| Panier multi-articles et remise caissier | règles de prix serveur inchangées |
| QR public malformé / abus de quotas | requête refusée sans écriture sensible |
| Ajout client CRM sans vente | aucune mutation stock / chiffre d'affaires |
| Historique vente sans contact | vue fonctionne, contact nullable |
| Assistant Gemini depuis caisse partagée | refus sans fuite de données propriétaire |
| Restaurant / salon | routes, caisse et réservations inchangées |
| Dates à minuit / changement de fuseau | agrégats stables et explicitement localisés |
| CI et SQL | lint, format, types, build, Vitest, offline, SQL passent |

## 6. Processus de livraison recommandé

1. Une PR par module, basée sur le `main` à jour ; aucun commit direct dans `main`.
2. Premier changement CRM : migration additive + tests SQL séparés ; ne pas introduire d'écritures sans politiques RLS.
3. Prévisualisation sur base **de test**, jamais les données de clients de production ; données anonymisées/simulées.
4. Gate avant fusion : CI complète verte, revue SQL, tests manuels mobile/Windows, contrat de rollback, feature flag désactivé par défaut.
5. Déploiement futur en deux temps : base additive validée, puis Edge/client ; vérification de la version effectivement active sur Vercel et Supabase.
6. Rollback : privilégier désactivation du flag et ancien frontend ; éviter d'effacer des colonnes ou tables contenant des données réelles.
7. Noter la personne qui a approuvé, l'horodatage et les commits précis.

## 7. Décision à ce stade

**Go** pour la préparation des tests P0 et du CRM additif sur branche isolée.  
**No-go** pour toute fusion, migration de production ou import massif de code tiers avant vérification CI + RLS + cohérence financière.

Ce document constitue la base de revue. Son ajout seul ne change **aucun** comportement de COVI.
