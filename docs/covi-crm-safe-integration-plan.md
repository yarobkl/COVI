# COVI — CRM natif : plan d'intégration progressif (22 octobre 2026)

**Statut : conception et utilitaires purs uniquement, sans activation de fonction CRM.**
Aucune modification des tables, ventes, flux caisse, synchronisation hors ligne, secrets ou déploiements.

## 1. Constat vérifié sur `main`

- Application React / TypeScript / Vite, Supabase Auth / PostgreSQL / Storage / Edge Functions, Tauri.
- Domaines existants : vente, arrivages, stock, personnel, commande publique, restaurant, salon, assistant Gemini.
- `record_sale` est le point d'écriture atomique des ventes; ne jamais créer un second moteur de caisse.
- PR #52 à #58 fusionnées : vérifier l'état réel des migrations et Edge Functions avant toute activation.
- Les images produits sont privées. Les données commerciales et les conversations IA ne doivent pas être transmises à des outils externes sans base légale et autorisation.

## 2. Décision d'intégration open source

- **Twenty** : inspiration UX CRM (contacts, recherche, historique), ou API externe étudiée séparément. Ne pas copier son code serveur AGPLv3 dans COVI sans revue de licence.
- **Trigger.dev** : option à comparer à Supabase Cron / Edge Functions pour des tâches réessayables. Ne pas ajouter de service tant que le besoin n'est pas démontré.
- **Medusa** : architecture et concepts de commandes ; ne pas installer son moteur commerce qui ferait doublon avec les ventes Supabase.
- **Gemini** : conserver le serveur `covi-assistant` et sa vérification d'identité ; aucune nouvelle clé dans React.

## 3. Modèle de données proposé (NON appliqué)

Table `crm_contacts` :
- `id uuid primary key`
- `shop_id uuid not null references shops(id)`
- `kind text check (kind in ('customer','supplier','both'))`
- `display_name text not null`
- `email text null`, `phone text null` (données facultatives)
- `notes text null` (accès limité au propriétaire/personnel autorisé)
- `marketing_consent_at timestamptz null`, `marketing_consent_source text null`
- `created_at`, `updated_at`

Liaisons **futures** : table `crm_contact_sale_links` avec `shop_id`, `contact_id`, `sale_id`, contrainte composite garantissant même boutique, liaison facultative. Aucun backfill de contact à partir de clics QR ou du numéro de téléphone sans vérification.

**Sécurité impérative** : RLS par `shop_id` et identité propriétaire ou membre autorisé. Les utilisateurs anonymes ne peuvent ni lire ni écrire. Fonctions SECURITY DEFINER uniquement si justifiées, `search_path` fixe, permissions EXECUTE minimales. Interdire toute référence inter-boutiques. Tester avec deux propriétaires et une caisse partagée.

## 4. Règles produit

1. Aucun contact obligatoire pour vendre : caisse et commandes existantes inchangées.
2. Email et téléphone sont des indices de doublon, jamais des preuves d'identité ni des clés mondiales.
3. Un numéro local ne doit pas être comparé sans code pays.
4. Aucun rapprochement automatique entre boutiques, même avec un email identique.
5. Aucune relance marketing sans consentement traçable ; prévoir accès, rectification, export, suppression et rétention.
6. L'assistant Gemini n'obtient pas de données CRM tant qu'une politique minimale de divulgation, des RPC de lecture et des tests d'autorisation ne sont pas établis.
7. Les sommes financières proviennent exclusivement des RPC / agrégats métier vérifiés, pas d'un LLM.

## 5. Séquence des futures PR (chacune réversible)

**A — Fondation sans effet de bord (cette branche) :** utilitaires purs d'identité CRM + tests, présent document. Aucun branchement à la navigation et aucune migration.

**B — Base CRM :** migration additive, RLS, index sur `shop_id`, politiques de suppression et tests SQL multitenant; générer les types; vérifier la compatibilité avec les migrations de `main`.

**C — Interfaces :** espace Clients / Fournisseurs adapté à « Le Cahier », formulaire accessible et mobile, recherche paginée, fusion manuelle avec journal d'audit.

**D — Liaison de ventes :** association facultative du contact *après* vente confirmée, jamais depuis une requête publique non validée. Tests de stock, prix, idempotence et rôles.

**E — Automatisations :** alertes et rapports opt-in sans exposition de coordonnées client; comparer d'abord Supabase Cron, puis Trigger.dev seulement si nécessaire.

**F — Gemini :** fonctions de lecture CRM strictement contrôlées par boutique, consentement et logs d'audit; pas d'écriture par le modèle.

## 6. Critères avant fusion et publication

- `npm ci`, `npm run format:check`, `npm run lint`, `npm run typecheck`, `npm run build`, `npm test`.
- `bash tests/sql/run.sh` dans PostgreSQL local isolé pour toute PR ajoutant des migrations.
- Scénarios de non-régression : vente simultanée; pièce unique; panier hors ligne et anti-doublon; caisse partagée; retours restaurant; commande QR; séparation boutique A / B; Gemini sur session caissier.
- Vérifier les statuts CI et la version exacte des migrations en environnement de staging.
- **Aucune fusion ou déploiement automatique depuis cette branche.**

## 7. Retour arrière

A : suppression des deux fichiers de logique/tests et de ce document. Aucune donnée à migrer.
B et suivantes : déployer par feature flag désactivé; revenir au code précédent sans effacer les données CRM. Une suppression de tables ne doit jamais être un rollback automatique.

## 8. Points non vérifiés

- État réel des migrations en production, secrets, configurations Vercel et Supabase.
- Diff et maturité de toutes les branches historiques.
- Tests d'intégration avec données et identités réelles, non exécutés durant l'analyse GitHub seule.
