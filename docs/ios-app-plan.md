# COVI iOS — chantier d'application mobile

Date de démarrage : 2026-11-05. Branche de préparation : `feature/covi-ios-capacitor`.

## Périmètre et invariants

- **Une seule plateforme métier** : l'app iOS consomme les services COVI existants, elle ne crée ni backend ni base en parallèle.
- **Trois métiers dans une seule application** : boutique, restaurant et salon de coiffure, avec la même gestion des rôles, établissements et droits.
- **Identité de marque préservée, expérience iPhone repensée** : conserver le logo, le bleu COVI, le vocabulaire métier et les données ; créer une coque iOS dédiée avec typographie système, cartes épurées, navigation basse et gestes tactiles. Le design web existant reste intact.
- **Production intacte** : aucun changement de `main`, du domaine web public, du projet Supabase de production ni de ses données pendant l'initialisation.
- **Connexion Apple reportée** : ne pas toucher aux boutons Google / Facebook avant activation et test du fournisseur Apple.
- **App ID provisoire** : `com.yaroconsulting.covi` est le même identifiant que dans `src-tauri/tauri.conf.json`. Le confirmer dans Apple Developer avant signature et premier build distribué.

## Choix technique

Conserver React + TypeScript + Vite, avec Capacitor comme conteneur iOS. Charger le **bundle local** compilé dans `dist` (pas une simple WebView affichant le site public) et communiquer avec Supabase sur HTTPS. Conserver Tauri pour Windows, sans le fusionner avec l'emballage iOS.

```
COVI web (React / Vite / design existant)
       |
       +--> Vercel : application web existante
       |
       +--> Capacitor iOS : bundle dist embarqué
                     |
                     +--> Auth + PostgreSQL + Storage + RPC Supabase existants
                     +--> Capacités iPhone : partage natif, appareil photo/QR, haptique (après tests)
```

## Étapes de livraison

### 1. Socle iOS

- [x] Préparer `capacitor.config.json` sur une branche dédiée.
- [x] Créer la base de la coque visuelle iOS exclusivement activée par le pont Capacitor natif (page header, tab bar flottante, fonds et cartes). **Non testée sur un simulateur/iPhone à ce stade.**
- [ ] Installer `@capacitor/core`, `@capacitor/cli`, `@capacitor/ios` avec **versions verrouillées** ; mettre à jour `package-lock.json` par `npm install`.
- [ ] Exécuter `npm ci`, `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`.
- [ ] Générer le dossier `ios/` avec `npx cap add ios`, puis `npx cap sync ios` dans un environnement macOS disposant de Xcode pris en charge.
- [ ] Ne jamais connecter le runtime mobile à l'environnement de préproduction par erreur ; employer des variables de build explicites.

### 2. Direction produit et design iOS

- [x] Prendre comme direction **application iPhone premium**, pas copie du site : la marque est commune, les interfaces sont différenciées.
- [x] Mettre en place `src/lib/nativePlatform.ts` et des styles `src/styles/app/ios.css` activés uniquement dans l'app native. Le rendu Safari reste inchangé.
- [ ] Tester sur iPhone : couleurs, contrastes, widgets de données, hauteurs et boutons >= 44 pt, clavier, safe areas et affichage Dynamic Type.
- [ ] Repenser écran par écran sans toucher aux règles métier : accueil/KPI, caisse, stocks, tables/commandes restaurant, agenda salon, paramètres.
- [ ] Utiliser des gestes natifs ou équivalents fiables pour les feuilles modales, retour, partage et feedback haptique lorsque justifiés.
- [ ] Vérifier les performances sur appareils modestes (animation, rafraîchissement de données, scrolling fluide), accessibilité VoiceOver et réduction des animations.
- [ ] Conserver des options de navigation lisibles pour les trois métiers ; ne pas faire du style une régression fonctionnelle.

### 2. Compatibilité iOS

- [ ] Tester l'écran de connexion et le flux email/password dans WKWebView, retour à l'app après session expirée, renouvellement et déconnexion.
- [ ] Tester OAuth Google via navigateur système et retour sécurisé par deep link/Universal Link ; ne pas supposer qu'une redirection Web fonctionne dans l'app iOS.
- [ ] Tester le stockage de session (ne jamais mettre de service-role dans le bundle).
- [ ] Vérifier la caméra, les liens QR, le partage de reçus, les fichiers, le clavier et les safe areas sans refonte visuelle.
- [ ] Tester l'état réseau : en ligne, hors ligne, reprise et anti-doublon sur vente.

### 3. Recettes par métier

- [ ] Boutique : création établissement, arrivages, stock, caisse, ventes, charges, résultats, vente offline et synchronisation.
- [ ] Restaurant : QR/table, menu, commande client, préparation cuisine, service, encaissement, fermeture et contrôle des droits.
- [ ] Salon : services, horaires, réservation, confirmation, collaborateurs, tickets, encaissement et suivi.
- [ ] Multi-établissements : ajout (maximum 3), changement, isolation des données et rôles employés.

### 4. Sécurité, qualité et conformité

- [ ] Recette sur projet de test Supabase avec des comptes fictifs ; ne pas créer des opérations fictives en production.
- [ ] Vérifier politiques RLS, accès aux ressources privées et journalisation des erreurs.
- [ ] Évaluer la facturation des abonnements numériques dans une app iOS au regard des règles App Store avant toute activation d'un paiement.
- [ ] Contrôler la règle 4.2 Apple : présenter une application de gestion fonctionnelle, avec utilité réelle et intégrations iPhone ; pas un simple site web emballé.
- [ ] Préparer la démonstration de toutes les fonctions nécessitant un compte pour l'équipe App Review.

### 5. Distribution

- [ ] Créer ou confirmer le Bundle ID et la fiche COVI dans App Store Connect.
- [ ] Configurer les capacités et la signature via le Team ID autorisé dans Apple Developer (ne pas stocker clés/certificats privés dans Git).
- [ ] Générer l'archive iOS `.ipa` dans Xcode ou sur un runner macOS sécurisé.
- [ ] Envoyer un build **TestFlight interne** et vérifier les trois parcours métier sur iPhone réel.
- [ ] Corriger les blocages, préparer la confidentialité et les captures App Store.
- [ ] Soumettre à App Review uniquement après validation explicite.

## Commandes de préparation (non exécutées sur cette branche)

```bash
npm install --save-exact @capacitor/core @capacitor/ios
npm install --save-dev --save-exact @capacitor/cli
npm run build
npx cap add ios
npx cap sync ios
npx cap open ios
```

**État réel :** configuration initiale créée ; dépendances iOS, projet Xcode, archive IPA et TestFlight non encore générés ni vérifiés. Une branche GitHub, même valide, n'est pas une app iOS livrée.
