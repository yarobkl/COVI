# COVI iOS — chantier d'application mobile

## Identité commerciale et gratuité — décision du 05/11/2026

- **Nom** : COVI.
- **Signification** : **Commerce & Vie** ; la vision de marque relie l'activité commerciale à la vie quotidienne (« la vie, c'est le commerce »).
- **Application iOS** : gratuite au téléchargement et **aucun abonnement, achat intégré ou fonctionnalité payante dans l'app COVI** au lancement, conformément à la décision du porteur de projet.
- **App Store Connect** : sélectionner le prix **Gratuit** lors de la création de la fiche COVI ; aucune configuration de paiement intégré.
- **Cohérence produit** : l'ancien modèle d'abonnements documenté pour le site / SaaS doit faire l'objet d'une migration produit distincte et vérifiée avant de modifier des droits ou facturations en production. Ne pas créer de faux blocages payants dans l'app iOS.
- **App ID Apple confirmé** : `com.covi.app` (compte individuel, Team ID `UK4UQCQ57G`). L'identifiant macOS/Tauri est distinct et reste inchangé.

Date de démarrage : 2026-11-05. Branche de préparation : `feature/covi-ios-capacitor`.

## Périmètre et invariants

- **Une seule plateforme métier** : l'app iOS consomme les services COVI existants, elle ne crée ni backend ni base en parallèle.
- **Trois métiers dans une seule application** : boutique, restaurant et salon de coiffure, avec la même gestion des rôles, établissements et droits.
- **Identité de marque préservée, expérience iPhone repensée** : conserver le logo, le bleu COVI, le vocabulaire métier et les données ; créer une coque iOS dédiée avec typographie système, cartes épurées, navigation basse et gestes tactiles. Le design web existant reste intact.
- **Production intacte** : aucun changement de `main`, du domaine web public, du projet Supabase de production ni de ses données pendant l'initialisation.
- **Connexion Apple reportée** : ne pas toucher aux boutons Google / Facebook avant activation et test du fournisseur Apple.
- **App ID iOS confirmé** : `com.covi.app` a été enregistré dans Apple Developer le 5 novembre 2026 (compte individuel, Team ID `UK4UQCQ57G`). L'identifiant macOS/Tauri est distinct et ne doit pas changer.

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
- [x] Créer une coque iOS beige exclusive au pont Capacitor : écran de connexion, logo officiel, navigation basse, cartes, accès rapide par métier, écran de lancement beige, changement d'établissement. Compilée pour le simulateur ; rendu visuel final et interactions sur iPhone réel restent à valider.
- [x] Installer `@capacitor/core`, `@capacitor/cli`, `@capacitor/ios` en version 8.6.0 avec `package-lock.json` régénéré en CI.
- [x] Exécuter `npm ci`, `npm run lint`, `npm test` et `npm run build` sur CI. Run vert : `https://github.com/yarobkl/COVI/actions/runs/42078691957` ; revalidation nécessaire pour les commits de l'interface suivants.
- [x] Générer le dossier `ios/` avec Xcode 26, `npx cap add ios` puis `npx cap sync ios` sur le runner macOS ; sauvegarder le projet Xcode en branche iOS uniquement.
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
- [ ] Générer l'archive iOS `.ipa` **signée** depuis Xcode/CI. Le build `.app` **simulateur** est produit, mais pas encore d'IPA signée.
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

**État réel (05/11/2026) :** un vrai projet Xcode Capacitor a été généré depuis le code métier COVI et compilé avec succès pour simulateur, dépendances verrouillées, tests web + build React verts sur le run 42078691957. CI iOS continue de vérifier les évolutions. Il reste la recette iPhone réel, les retours OAuth mobiles, la vérification des données entre établissements et la signature Apple pour TestFlight. L'application web et la base de production sont inchangées.


## Distribution et secrets Apple : sécurité

- Le Bundle ID de l'application iOS est **`com.covi.app`**, confirmé par la capture Apple Developer du 05/11/2026. L'App ID est prêt ; il reste à créer la fiche COVI App Store Connect et un profil de signature propre à cet identifiant.
- La distribution est **désactivée par défaut**. Le workflow `.github/workflows/ios-testflight.yml` exige un lancement manuel et `uploadToTestFlight=true`.
- Secrets requis, à enregistrer uniquement dans **GitHub Actions → Repository secrets** pour `yarobkl/COVI` : `APPLE_TEAM_ID`, `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_PRIVATE_KEY`, `APPLE_DISTRIBUTION_CERTIFICATE_P12_BASE64`, `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`, `APPLE_APP_STORE_PROFILE_BASE64`.
- La clé privée `.p8`, le certificat p12 et la provisioning profile **ne doivent jamais être committés ni publiés en chat**. Les secrets configurés pour GaspardNZ ne sont pas automatiquement accessibles dans le dépôt COVI.
- `workflow_dispatch` doit être accessible sur la branche par défaut de GitHub avant de pouvoir l'utiliser depuis l'onglet Actions. **Ne pas fusionner cette PR de manière automatique** pour ce seul motif.
- L'upload TestFlight n'entraîne ni validation App Review ni publication de l'application sur l'App Store.
