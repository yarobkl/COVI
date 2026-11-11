# COVI — Audit initial, 11 novembre 2026

## Périmètre inspecté
Dépôt yarobkl/COVI, branches main et feature/covi-ios-capacitor. README.md, package.json, supabase/config.toml, capacitor.config.json, src/main.tsx, src/app/Root.tsx, ios/App/App/Info.plist, .github/workflows/ios-testflight.yml.

## État observé
- Application React / TypeScript / Vite, backend Supabase, version desktop Tauri documentée sur main.
- Branche iOS Capacitor 8, bundle com.covi.app, ios:sync et intégration Apple Sign In déclarée dans package.json.
- Root.tsx détecte iOS, applique viewport-fit=cover et gère AuthGate / CounterGate.
- Workflow TestFlight manuel, conditionné à uploadToTestFlight=true.
- ATTENTION : le workflow checkout explicitement feature/covi-ios-capacitor, indépendamment de la branche depuis laquelle il est déclenché. Vérifier la provenance exacte des builds et éviter toute divergence avec la branche revue.
- Plusieurs Edge Functions dans supabase/config.toml ont verify_jwt=false; leur sécurité dépend de contrôles applicatifs à vérifier, pas seulement des commentaires.
- Info.plist contient ITSAppUsesNonExemptEncryption=false; vérifier la conformité de cette déclaration.
- README main semble plus ancien que l'état iOS et les fonctionnalités multi-établissements.

## Sept responsabilités de revue
1. Alexandre — coordination, architecture, priorités, arbitrages.
2. Sarah — parcours et design iOS, accueil, Commencer / Se connecter, accessibilité.
3. Kevin — Capacitor, navigation native, Apple Sign In, performance.
4. Amina — Supabase, RLS, isolation établissements, transactions, migrations.
5. David — secrets, JWT, Edge Functions publiques, confidentialité, conformité.
6. Chloé — tests, régressions, réseau faible, QA appareil.
7. Samuel — GitHub Actions, signature, versioning, provenance des builds, TestFlight.

Ces rôles sont des instructions de revue, **pas sept processus autonomes en exécution**. Respecter le AGENTS.md existant et les skills locaux du dépôt.

## Plan priorisé
P0 : vérifier RLS, fonctions publiques et isolation multi-établissements.
P0 : identifier le SHA réellement livré sur TestFlight et vérifier le pipeline de distribution.
P1 : exécuter npm ci, typecheck, lint, test, build sur checkout isolé.
P1 : tester sur iPhone Apple Sign In, premier lancement, navigation, safe areas et parcours métier.
P1 : documenter les défauts et corriger par pull requests avec preuve et retour arrière.
P2 : mettre à jour la documentation et réconcilier les branches.

## Limites de cette première revue
Aucun test automatisé exécuté, aucune connexion à la base Supabase ni à App Store Connect, aucune inspection exhaustive des migrations ou des Edge Functions. Le statut TestFlight est déclaré par le propriétaire, non revérifié. Aucune production modifiée et aucun build distribué.
