# COVI iOS — SwiftUI natif

## Démarrage
1. Créer un projet **iOS App** nommé `COVI` dans Xcode (SwiftUI, Swift, iOS 17+).
2. Ajouter le dossier `COVI/` au projet, avec tous les fichiers `.swift` dans la target.
3. Supprimer le fichier `App` généré par le template afin de ne conserver qu'un seul `@main` (`COVIApp.swift`).
4. Configurer le Team ID et le bundle identifier dans Signing & Capabilities.
5. Compiler sur simulateur iPhone, puis intégrer les 46 écrans par fonctionnalité.

## État réel
- SwiftUI et SwiftData locaux pour Boutique, Restaurant et Salon ; aucune WebView ni API Supabase.
- Identité locale en Keychain ou Sign in with Apple (identifiant stable entre appareils).
- CloudKit privé : répertoire d'établissements et journal de **renommages et remboursements uniquement**.
- Le stock, les réservations, les articles, les encaissements et les fiches clients **ne sont pas encore synchronisés entre appareils**.
- La caisse est accessible sans PIN au propriétaire qui n'a pas installé de code ; le personnel et les propriétaires ayant configuré un code passent par un verrou local.
- Réception de paiements en caisse uniquement. COVI n'encaisse pas de monnaie électronique.
- Reçus natifs vérifiés à partir des lignes et du règlement enregistré, partageables par la feuille système.
- L'entitlement Sign in with Apple est déclaré dans la cible, mais la validation de la capacité sur le profil Apple **déjà existant** doit être effectuée au moment de compiler. Ne jamais modifier les certificats/profils automatiquement.
- L'historique hybride/Supabase ne migre pas automatiquement vers l'identité locale/Apple. Une migration explicite et testée est nécessaire.
- Le code Swift n'a pas été compilé dans cet environnement Linux : voir `PROGRESS_TRACKER.md`.
