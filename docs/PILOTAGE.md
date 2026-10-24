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
- Branches des agents (toutes intégrées à `integration/preprod`) : `agent/cla-02-preprod`, `agent/cla-03-recette-boutique`,
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

Fichiers : `tests/sql/recette_boutique.sql`, `recette_restaurant.sql`, `recette_salon.sql`, intégrés
à `integration/preprod` et lancés par `tests/sql/run.sh` (donc par `test-db` en CI). Exécution
vérifiée par CLA-01 après intégration : **43/43 suites SQL vertes**. Chaque contrôle porte l'ID du
scénario dans la sortie. Les écarts sont **constatés** par le test, pas corrigés.

**Boutique (CLA-03)** — RET-001, 002, 003, 004, 007, 008, 010 : PASS (SQL). RET-005 : PASS
(`cart_concurrency.sh`, `members_concurrency.sh`). RET-006 : PASS côté serveur (rejeu) et client
simulé (`tests/offline.mjs`) ; vraie coupure réseau non testée (E2E). FIN-001 : PASS (CA 14 000,
coût 8 000, marge 6 000, résultat 5 000). **RET-009 : écart avec la spécification** — remise de 50 %
acceptée pour un caissier plafonné à 10 % ; le plafond a été retiré volontairement par
`20261015120000_shop_requested_order_fixes` (« corrections demandées par la boutique »). La
spécification RET-009 est donc à mettre à jour, ou la décision à revoir par le propriétaire.
À confirmer avec GPT-05 : le coût d'un ballon est réparti par pièce enregistrée (choix documenté de
`shop_aggregates`) et le champ de l'excédent s'appelle `profit` : vérifier qu'il n'est pas présenté
comme un bénéfice net.

**Restaurant (CLA-04)** — Capacités : QR lecture seule actif ; commande de groupe QR désactivée par
défaut (double interrupteur) ; remboursement en espèces seulement, via incident validé par le
propriétaire ; remises et paiement mixte non implémentés. RES-002 à RES-009 et RES-011 : PASS (SQL,
plus `restaurant_concurrency.sh`, `restaurant-qr-gateway` 5/5, `restaurant-guest-gateway` 6/6).
RES-001 et RES-012 : PASS côté serveur, rendu et coupure réseau BLOQUÉS (pas de navigateur relié à
une base). RES-010 : BLOQUÉ (impression réelle). Aucune anomalie confirmée. Risques à traiter :
`restaurant_staff_add_item` n'a pas de clé d'opération (un ajout rejoué après réponse perdue créerait
une seconde ligne) ; un renvoi de commande personnel reçoit « Session not collecting » au lieu de la
référence existante (pas de doublon, mais message à traiter dans l'écran).

**Salon (CLA-05)** — SAL-001 à SAL-011 : PASS (68 contrôles SQL, plus `salon_concurrency.sh`).
SAL-013 : BLOQUÉ (visuel ; vitest Salon 42/42). SAL-014 : PASS partiel (aucune fonction `salon_*`
exécutable par `anon`, refus sans session ; migration partielle non simulée). FIN-002, 003, 005,
006 : PASS, montants conformes au référentiel (FIN-002 : CA 18 000, marge 13 000, commissions 1 200,
résultat 10 300).
**ANO-FIN-001 confirmée (SAL-012 / FIN-004)** — vente 12 000 le 28/09, remboursée le 05/10, mesuré
dans `salon_report` : septembre CA **0** (12 000 avant le remboursement), encaissé 12 000 ; octobre
CA **0**, remboursé 12 000, net −12 000. La trésorerie est juste ; le CA de septembre est modifié
rétroactivement et octobre ne porte pas l'ajustement. Cause : filtre `l.refunded_at is null` dans
`20261024095000_salon_pro_reports.sql`. Non corrigé : décision du propriétaire requise.
**ANO-UX-001 partiellement confirmée** — le message réseau de `salonErrorMessage`
(`src/lib/salon.ts`) affirme « rien n'a été enregistré », ce qui peut être faux si la réponse est
perdue ; en revanche les clés de paiement et de remboursement sont conservées jusqu'au succès (pas de
double encaissement, prouvé par SAL-008/009). Un nouveau ticket vide peut être créé en double.
Point à arbitrer : le coiffeur voit nom et téléphone du client sur ses propres rendez-vous (conforme
à `docs/salon/AUDIT-ET-ARCHITECTURE.md`, à confirmer au regard de SAL-006).

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
5. RET-009 : confirmer l'absence de plafond de remise caissier (ou le rétablir).

## Section ChatGPT

_(à tenir par l'équipe ChatGPT)_
