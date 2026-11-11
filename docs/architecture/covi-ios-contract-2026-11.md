# COVI iOS — Contrat d'architecture et de livraison

Statut : plan de travail, **pas** une validation de tests ou de maquette. Référence graphique : la maquette approuvée à trois iPhone (accueil, connexion, création de compte), fournie par le propriétaire le 11 novembre 2026.

## Invariants non négociables
- Ne modifier ni le site web de production ni ses parcours; conserver la base métier et Supabase partagés avec les contrôles d'accès existants.
- Isoler les adaptations iOS (React/Vite/TypeScript/Capacitor et Xcode); pas de réécriture SwiftUI ni de changement de plateforme sans décision.
- Aucun merge vers main, build TestFlight, déploiement, modification de maquette ou publication App Store sans validation explicite du propriétaire.
- Aucun secret Apple, token Supabase service-role ou certificat dans Git ou les rapports.
- Trois métiers préservés : Boutique, Restaurant, Salon; trois établissements maximum par utilisateur; espaces et rôles strictement cloisonnés.

## Découpage de responsabilités techniques
1. **Présentation iOS** : accueil, connexion, création de compte, composants, safe areas, typographie, transitions, clavier et accessibilité. Le rendu doit correspondre à la maquette et être vérifié sur captures d'écran iPhone.
2. **Orchestration de parcours** : machine d'états explicite accueil → connexion / inscription → confirmation email / OAuth → chargement du compte → choix ou création d'établissement. Les deux CTA d'accueil ne peuvent jamais mener au même écran.
3. **Identité et session** : Supabase Auth email/mot de passe, Apple, Google si activés; retours OAuth et liens profonds; erreurs visibles; session persistante; réinitialisation de mot de passe; déconnexion et fermeture des sessions de caisse.
4. **Domaine métier** : Boutique, Restaurant, Salon; établissements et équipe; ventes, stocks, caisse, tables/QR et rendez-vous. Conserver les règles et contrats des fonctions existantes; éviter toute duplication de logique métier dans l'UI iOS.
5. **Données et autorisations** : API Supabase partagée, RLS vérifiée par table et rôle, owner/caissier/personnel séparés, contrôles de concurrence et de double soumission, gestion des erreurs réseau.
6. **Qualité et livraison** : tests unitaires/intégration, parcours de bout en bout, captures comparatives, vérification de la branche et des assets empaquetés, version iOS croissante, archive signée, TestFlight interne uniquement.

## Répartition des sept rôles
| Rôle | Responsabilité | Preuve de sortie attendue |
|---|---|---|
| Alexandre — architecture/orchestration | Diagramme des dépendances, frontières web/iOS, contrats d'authentification et de domaine, arbitrage des changements | Note d'architecture et revue des impacts |
| Sarah — UX/UI | Inventaire de chaque élément des trois maquettes, mesures, design tokens, états de chargement et d'erreur | Comparatif maquette/capture pour chaque écran |
| Kevin — iOS/frontend | Implémentation isolée des écrans et transitions; branchements fonctionnels des CTA | Diff de code, tests UI et captures sur appareil |
| Amina — backend/logique métier | Maintien des contrats Supabase, inscription et établissement, règles Boutique/Restaurant/Salon | Matrice des parcours et tests métier |
| David — sécurité | OAuth Apple/Google, sessions, RLS, confidentialité, secrets et permissions | Revue des risques et tests d'accès négatifs |
| Chloé — QA | Tests de navigation, clavier, petits écrans, offline, doubles actions et non-régression | Rapport de tests avec résultats observés et défauts |
| Samuel — DevOps | Vérification ref/commit, signature, version/build, upload TestFlight, traçabilité | Journal du build et confirmation de la version disponible |

**Important :** ces sept rôles sont des responsabilités documentées, pas des agents autonomes en cours d'exécution. Un rapport n'est marqué « exécuté » qu'avec une preuve vérifiable.

## Critères d'acceptation des trois écrans
- Accueil : logo compact; titre sur trois lignes tel que la maquette; secteurs avec pictogrammes; visuel téléphone montrant COVI (pas de graphique générique); CTA « Commencer » et « Se connecter » visibles sans défilement sur l'iPhone cible.
- Connexion : email et mot de passe; récupération; CTA; Apple/Google selon configuration; lien vers inscription; gestion des erreurs, clavier et chargements.
- Création de compte : email, mot de passe et confirmation; Apple/Google selon configuration; lien retour connexion. Les informations métier supplémentaires peuvent suivre après authentification, sans suppression des règles existantes.
- Respect des safe areas, de VoiceOver, des tailles tactiles et de Reduce Motion; aucun débordement sur iPhone.
- Le test ne peut pas être déclaré réussi sans captures réelles comparées à la référence.

## Séquence de travail
1. Auditer `src/features/auth/AuthGate.tsx`, `LoginForm.tsx`, `AuthPage.tsx`, les styles auth, le chargement d'assets iOS, les routes et les fonctions Supabase.
2. Décrire le flux actuel et les écarts par rapport au contrat ci-dessus; identifier les risques de régression web.
3. Corriger sur une branche iOS isolée; conserver les interfaces publiques et la logique métier existante.
4. Exécuter `npm run typecheck`, `npm run lint`, `npm test`, `npm run build` si environnement disponible; consigner les résultats réels.
5. Capturer les trois écrans sur un simulateur/appareil et comparer avec la maquette; obtenir la validation du propriétaire.
6. **Seulement après accord** : déclencher un nouveau build TestFlight, contrôler son contenu et sa disponibilité; ne jamais soumettre à App Review automatiquement.

## Questions techniques à trancher lors de l'audit
- L'accueil et les formulaires sont-ils mutualisés avec le web ? Comment les isoler sans affecter la production ?
- Le flux Google natif revient-il correctement dans l'app iOS ? Apple crée-t-il/relie-t-il le bon compte ?
- Quelles données supplémentaires de profil/commerce doivent être demandées après l'inscription simplifiée ?
- Quels tests automatiques protègent le choix de trois établissements, les rôles et la prévention des doubles opérations ?

Ce document est une base de travail; il ne prétend ni avoir corrigé l'interface ni avoir exécuté des tests.
