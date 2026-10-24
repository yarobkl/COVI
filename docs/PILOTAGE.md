# COVI — Pilotage préproduction

Document partagé. Chaque équipe tient **sa** section ; on ne modifie pas celle de l'autre.
Règle de lecture : « exécuté » = lancé réellement avec sortie vérifiée ; « annoncé » = rapporté sans
exécution vérifiable. Un scénario non exécuté n'est jamais marqué PASS.

## Section Claude Code (CLA-01 à CLA-07)

Mise à jour : 24/10/2026. Branche de référence : `integration/preprod`.

### CLA-01 — Intégration

- `integration/preprod` = `feature/covi-salon-professional-v1` (PR #64) + `feature/covi-refonte-wave`
  (PR #66) + `agent/cla-02-preprod` (kit préproduction). Fusions sans conflit.
- Exécuté localement sur cette branche : typage OK, build OK, lint OK, formatage OK, 367/367 tests
  web, tests hors ligne, notifications cuisine 6/6, assistant 16/16 ; suite SQL complète (voir CLA-02).
- CI GitHub : `test-web` et `test-db` ne tournaient que sur les PR vers `main`. Ils sont maintenant
  déclenchés aussi par un push sur `integration/preprod` (le build Windows reste exclu sur cette
  branche pour ne pas consommer de minutes payantes).
- Branches des agents : `agent/cla-02-preprod`, `agent/cla-03-recette-boutique`,
  `agent/cla-04-recette-restaurant`, `agent/cla-05-recette-salon`. Aucune fusion dans `main`.

### CLA-02 — Supabase préproduction

- **Migrations réellement appliquées sur `stcsjwxmmxnjwisqkudz` : aucune.** Le connecteur Supabase
  de Claude ne voit pas l'organisation Testcovi : `list_projects` ne liste pas le projet et
  `get_project(stcsjwxmmxnjwisqkudz)` répond « You do not have permission to perform this action »
  (vérifié trois fois le 24/10). Aucune écriture tentée, aucune bascule vers la production.
- Répétition locale (PostgreSQL 16 jetable + stubs Supabase de `tests/sql/bootstrap.sql`) :
  72/72 migrations dans l'ordre, purge remplacée par `preprod_account_purge_schedule.sql`, puis
  `seed_retail_restaurant.sql` et `seed_salon.sql` chargés deux fois sans doublon.
- Défauts du kit trouvés et corrigés pendant cette répétition :
  1. la purge de remplacement échouait sans pg_cron (`relation "cron.job" does not exist`), donc à
     coup sûr sur un projet neuf ;
  2. `seed_salon.sql` n'était pas rejouable (« Client name is required » au second passage).
- Preuves RLS (`supabase/preprod/verify_preprod.sql`, exécuté en local) : 74/74 tables de `public`
  avec RLS ; `anon` n'a le droit SELECT sur aucune ; 0 fonction SECURITY DEFINER sans `search_path` ;
  aucune référence à la production ; chaque propriétaire fictif ne voit que son établissement, un
  coiffeur ou un inconnu ne voit rien, les tables Salon ne sont lisibles que par les fonctions.
- `btree_gist` (contraintes d'exclusion Salon) : créé par les migrations Salon, vérifié par la
  répétition locale.
- Limite : les stubs locaux imitent Supabase ; ces preuves seront à rejouer sur la cible
  (`verify_preprod.sql` + advisors de sécurité) dès que l'accès existe.

### CLA-03 / CLA-04 / CLA-05 — Recettes métier

Voir les tableaux de résultats ci-dessous (exécutés en base locale, pas en préproduction).

<!-- RECETTES -->

### CLA-06 — UX et Wave

- **Bloqué.** Aucune base de préproduction joignable, pas de Docker dans l'environnement Claude
  (donc pas de pile Supabase locale), et lancer l'application sans `VITE_SUPABASE_URL` la brancherait
  sur la **production** (`src/lib/supabase.ts`). Aucune capture « avec données » ne peut donc être
  produite honnêtement.
- Ce qui est vérifié : les tests de composants (vitest, 367/367) sur la branche d'intégration.

### CLA-07 — CI/CD, E2E, Cloudflare, retour arrière

- **Cloudflare « Workers Builds: covi »** : en échec sur les PR #64 et #66 et sur `main`. L'échec est
  instantané (début = fin), sans journal côté GitHub ; le détail n'est visible que dans le tableau de
  bord Cloudflare. Le dépôt ne contient aucune configuration Workers (`wrangler.toml` / `.jsonc`) : la
  cause probable est un projet Workers relié au dépôt sans configuration de build. À confirmer par le
  propriétaire dans Cloudflare. Ce check ne valide ni la base ni les règles métier ; il ne doit pas
  être ignoré : soit le projet Workers est réparé, soit il est débranché du dépôt. Le domaine
  `covi.eliebakala.workers.dev` est encore autorisé par `restaurant-qr` : à garder cohérent.
- **Aperçus Vercel** : chaque push sur `integration/preprod` produit un aperçu. Claude n'a pas le droit
  de lire les variables Vercel ; sans `VITE_SUPABASE_URL` de préproduction, l'aperçu utilise la
  production. **Interdiction d'utiliser ces aperçus pour tester** tant que le propriétaire n'a pas
  défini, pour l'environnement Preview limité à la branche `integration/preprod` :
  `VITE_SUPABASE_URL=https://stcsjwxmmxnjwisqkudz.supabase.co` et `VITE_SUPABASE_PUBLISHABLE_KEY`
  (clé publique de préproduction). Vérification à l'exécution : l'onglet Réseau doit montrer
  `stcsjwxmmxnjwisqkudz` et jamais `bmbwmwgfzrijglzcgjut`.
- **E2E** : prêts à écrire dès qu'un aperçu est relié à la préproduction ; Playwright est disponible.
  Parcours prévus : connexion de chaque compte de test, une vente boutique, une table restaurant de
  l'ouverture au règlement, un rendez-vous salon jusqu'au paiement, à 390 et 1280 px.
- **Mise en production (quand le propriétaire l'autorise)** : 1) sauvegarde/point de restauration
  Supabase production ; 2) migrations additives dans l'ordre, une par une, arrêt au premier échec ;
  3) vérifications `verify` en lecture seule ; 4) déploiement front ; 5) parcours de contrôle.
  **Retour arrière** : front = redéployer la version précédente sur Vercel ; base = pas de
  suppression de données : les objets Salon `salon_*` (migrations `20261024090000` à
  `20261024095000`) peuvent être retirés tant qu'aucune donnée réelle n'y est écrite, sinon on
  désactive l'accès côté front et on conserve les tables.

### Blocages qui demandent le propriétaire

1. Donner à Claude l'accès Supabase au projet `stcsjwxmmxnjwisqkudz` (ou exécuter le fichier
   d'installation unique fourni dans la conversation, dans le SQL Editor de ce projet).
2. Variables Vercel Preview pour `integration/preprod` (ci-dessus).
3. Cloudflare Workers : réparer ou débrancher.
4. Décision FIN-004 (remboursement d'un mois sur l'autre).

## Section ChatGPT

_(à tenir par l'équipe ChatGPT)_
