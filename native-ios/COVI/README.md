# COVI iOS — Starter natif SwiftUI

## Démarrage
1. Créer un projet **iOS App** nommé `COVI` dans Xcode (SwiftUI, Swift, iOS 17+).
2. Ajouter le dossier `COVI/` au projet, avec tous les fichiers `.swift` dans la target.
3. Supprimer le fichier `App` généré par le template afin de ne conserver qu'un seul `@main` (`COVIApp.swift`).
4. Configurer le Team ID et le bundle identifier dans Signing & Capabilities.
5. Compiler sur simulateur iPhone, puis intégrer les 46 écrans par fonctionnalité.

## État réel
- Inclus : modèles SwiftData locaux, thème, politique de tabs dynamiques, garde PIN de navigation, outbox de base, retours haptiques.
- **Non inclus / non fonctionnel en production** : CloudKit, sync multi-utilisateur, provisioning des PIN, validation serveur, authentification, permissions effectives, écrans métier finaux, migrations, tests.
- Le `PINEntryView` ne reçoit pas encore d'identité ou de hash depuis une session : il **refuse l'accès** tant que le flux d'authentification n'est pas branché. C'est intentionnel.
- Ne pas utiliser SHA-256 seul pour protéger un PIN à quatre chiffres. Utiliser un KDF lent + Keychain et un contrôle d'accès serveur.
- Ne pas déduire une compatibilité CloudKit de ces modèles : une modélisation spécifique, contraintes et tests sont requis.
