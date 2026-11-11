# Audit statique initial — COVI iOS (11 novembre 2026)

**Portée** : lecture GitHub uniquement, sans exécution du projet, tests sur appareil, accès Supabase ni modification de production. Sources examinées : branche `main` et branche réellement désignée par le workflow `audit/covi-seven-roles-2026-11`.

## Résultats prioritaires

| Priorité | Observation confirmée | Impact | Correction proposée |
|---|---|---|---|
| P0 | `.github/workflows/ios-testflight.yml` sur `main` force `actions/checkout` à `audit/covi-seven-roles-2026-11` (ligne 45), indépendamment de la branche affichée par le workflow | Le commit visible dans GitHub Actions ne prouve pas le commit réellement empaqueté; risque de livrer un ancien design | Rendre la source explicite, journaliser et vérifier le SHA réellement compilé; exiger validation du propriétaire avant changement du pipeline |
| P0 | Sur la branche empaquetée, `AuthGate.tsx` lignes 176–213 code un graphique en cinq barres (`auth__welcome-dashboard-bars`) à la place du visuel téléphone de la maquette | Écart graphique avéré, reproduction non conforme | Remplacer par un asset approuvé et intégrer des contrôles de capture comparée |
| P1 | Sur la branche empaquetée, `AuthGate.tsx` utilise `showWelcome` + `mode` (lignes 62–63) pour le parcours iOS; `main` ne possède pas cet écran et démarre en `login` | Deux implémentations divergentes; risque de confusion entre code source et version iOS | Formaliser un état de navigation `welcome/login/signup/confirm/onboard` sans toucher aux parcours web |
| P1 | Sur la branche empaquetée, `LoginForm.tsx` propose une inscription email simplifiée sur iOS mais conserve l'inscription métier complète sur web (condition `!nativeIos`, lignes ~185–200) | Divergence intentionnelle à protéger; les règles métier doivent être appliquées lors de la création du commerce, pas supprimées | Tests séparés web/iOS; audit de `CreateShopForm` et des contrôles serveur avant changement |
| P1 | Sur la branche empaquetée, `LoginForm.tsx` traite Apple iOS avec `SignInWithApple.authorize` + `supabase.auth.signInWithIdToken`, mais Google passe par `signInWithOAuth` avec redirection URL | Retour Google natif non démontré par l'inspection; risque de sortie vers le navigateur ou de session non récupérée | Vérifier URL de retour, universal/deep links, réception des tokens et reprise d'application sur appareil |
| P1 | `AuthPage.tsx` est un conteneur partagé avec titre « Votre activité, mieux pilotée », secteurs et branding génériques | Le style partagé peut réintroduire des écarts et affecter le web | Séparer les variantes de présentation iOS sans dupliquer les fonctions d'authentification |
| P2 | `LoginForm.tsx` gère formulaires, appels Supabase, OAuth, reset et affichage dans un composant volumineux (600 lignes sur la branche iOS) | Forte concentration de responsabilités, tests et maintenance difficiles | Extraire des services/hooks testables pour auth, OAuth et état des formulaires |
| P2 | `AuthGate.tsx` gère session, chargement d'établissements, espaces caissier/restaurant/salon et navigation de l'authentification (424 lignes sur la branche iOS) | Risque de régression croisée | Isoler l'orchestration des espaces de la présentation onboarding |

## Points positifs à préserver
- Les CTA iOS **ne sont pas identiques** dans le code empaqueté : « Commencer » choisit `signup`, « Se connecter » choisit `login` (branche audit, `AuthGate.tsx` ~196–213).
- `AuthGate` conserve le chargement des établissements, les espaces de personnel et les sessions de caisse.
- `ownerSignup.ts` traite les métadonnées de profil comme des indications non fiables pour l'autorisation.
- Le workflow vérifie le numéro de version et de build dans l'archive avant upload; le contrôle de provenance du code reste insuffisant.

## Vérifications encore nécessaires
1. Lire les styles de l'accueil et des formulaires, les assets réels, la détection `isCoviIosApp`, la configuration Capacitor et les tests existants.
2. Inspecter `CreateShopForm`, `AddEstablishmentForm` et les contraintes serveur/RLS, notamment limite de trois établissements et permissions.
3. Tester sur appareil iOS : email, Apple, Google, confirmation email, reset, création de commerce, bascule d'établissements, fermeture de caisse, retour arrière et clavier.
4. Capturer et comparer les trois écrans à la maquette validée. Aucun score de conformité ne peut être donné sans rendu vérifié.

## Décision recommandée
Avant de modifier le design : sécuriser la provenance des builds et définir une séparation claire **UI iOS / orchestration d'auth / services Supabase / logique métier**. Ensuite, corriger les trois écrans sur branche dédiée, tests et captures, puis demander l'accord avant merge et TestFlight.

**Statut : audit statique partiel. Aucun test exécuté. Aucune correction de code applicatif ni déploiement effectué.**
