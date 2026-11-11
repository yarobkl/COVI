# COVI — Sprint 01 : première ouverture iOS et authentification

Date : 2026-11-11
Branche de travail : audit/covi-seven-roles-2026-11
Statut : cadrage initial, aucune modification applicative ni livraison TestFlight autorisée à ce stade.

## Sources inspectées
- Vidéo TestFlight et capture de l'ancien écran d'accueil fournies par le propriétaire.
- src/app/Root.tsx, src/features/auth/AuthGate.tsx, LoginForm.tsx, CreateShopForm.tsx, src/app/App.tsx, src/app/sectorNavigation.ts, src/styles/app/ios.css.
- Ne pas confondre la version TestFlight installée avec le code actuel de feature/covi-ios-capacitor sans vérification du commit de build.

## Décisions produit proposées, à valider
1. Accueil iOS natif : marque COVI, proposition de valeur concise, aperçu du produit, boutons Commencer (inscription) et Se connecter (connexion). Pas de faux indicateurs de pagination.
2. Connexion : Apple natif, Google si son flux iOS est vérifié, email/mot de passe ; ne pas afficher un fournisseur cassé.
3. Inscription : même fournisseurs et email ; une fois authentifié, création d'établissement par étapes, avec conservation des validations existantes.
4. Compte existant : accès direct à son espace, sans retour obligatoire à l'accueil.
5. Trois métiers : boutique, restaurant, salon conservent leurs routes, permissions, données et actions existantes.
6. Ne modifier ni les fonctions RPC, ni les règles RLS, ni les données de production dans ce sprint.

## Observations à confirmer
- AuthGate affiche l'accueil iOS si showWelcome et absence de session ou d'espace ; vérifier la logique pour session sans espace.
- Apple : SignInWithApple.authorize puis Supabase signInWithIdToken ; vérifier annulation, nonce, retour et première création.
- Google : chemin OAuth web présent ; vérifier explicitement le retour dans Capacitor iOS avant de promettre un parcours natif.
- Trois points de pagination dans l'accueil sans trois pages correspondantes dans AuthGate.
- Formulaire établissement très long ; des validations et limitations XAF sont fonctionnelles, ne pas les retirer par design.

## Répartition des sept rôles configurés OpenCode
- Alexandre (orchestrateur) : carte des parcours, dépendances, synthèse, arbitrages soumis au propriétaire.
- Sarah (UX/UI) : accueil, connexion, inscription, onboarding, design tokens et accessibilité.
- Kevin (iOS) : Capacitor, Apple/Google auth, safe areas, navigation, performance, comportement au retour.
- Amina (backend) : contrat Supabase auth, session, établissements et séparation multi-tenant ; lecture seule.
- David (sécurité) : vérification OAuth/OIDC, nonce, stockage session, permissions ; lecture seule.
- Chloé (QA) : matrice des parcours, tests de non-régression et preuves des résultats.
- Samuel (DevOps) : provenance du build TestFlight, CI, validation des secrets par présence seulement, sans révéler de valeurs ni déclencher de build/upload.

## Boucle de travail
Inspection factuelle -> proposition Sarah/Kevin -> contre-revue Amina/David -> tests Chloé -> revue Samuel -> arbitrage Alexandre -> validation du propriétaire -> implémentation sur branche isolée -> tests -> compte rendu.
Un rôle n'est pas un processus exécuté tant qu'OpenCode n'est pas lancé.

## Critères d'acceptation du sprint
- Les deux CTA mènent à des flux distincts.
- Apple et Google : tests réels sur appareil avant déclaration de réussite.
- E-mail : inscription, confirmation, connexion, mot de passe oublié, retour.
- Utilisateur déjà connecté -> bon espace ; nouvel utilisateur -> onboarding.
- Les trois secteurs restent utilisables ; aucun changement serveur ou production.
- Aucun merge, push de déploiement, build TestFlight ou upload sans validation explicite.
