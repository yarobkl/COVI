# COVI iOS — SwiftUI natif

## Démarrage
1. Ouvrir `native-ios/COVI.xcodeproj` dans Xcode, ou exécuter `xcodegen generate` depuis `native-ios/` pour le régénérer à partir de `project.yml`.
2. Utiliser un simulateur iPhone iOS 17+ pour compiler et exécuter les XCTest de la cible `COVITests`.
3. Conserver les paramètres de signature Apple existants : **ne jamais créer ou modifier automatiquement un certificat ni un profil de provisioning**.
4. Comparer chaque écran avec les 46 maquettes approuvées avant de déclarer la conformité visuelle.

## Vérification sans TestFlight

Le workflow GitHub Actions `COVI Native iOS Diagnostics` sur la branche isolée
`wip/covi-native-20261119-no-testflight` utilise un runner macOS et
`CODE_SIGNING_ALLOWED=NO`. Il **compile puis exécute les tests**, sans archive,
signature, livraison ni modification de Xcode Cloud.
La révision `765f157` a réussi ses 53 XCTest. Les modifications ultérieures
doivent être revérifiées sur ce workflow, puis testées sur un appareil réel.

## État réel
- SwiftUI et SwiftData locaux pour Boutique, Restaurant et Salon ; aucune WebView ni API Supabase.
- Identité locale en Keychain ou Sign in with Apple (identifiant stable entre appareils).
- CloudKit privé : répertoire d'établissements, journal de **renommages et remboursements**, et archive immuable des reçus confirmés.
- Le stock, les réservations, les articles, les commandes en cours et les fiches clients **ne sont pas encore synchronisés entre appareils**.
- La caisse est accessible sans PIN au propriétaire qui n'a pas installé de code ; le personnel et les propriétaires ayant configuré un code passent par un verrou local.
- Réception de paiements en caisse uniquement. COVI n'encaisse pas de monnaie électronique.
- Reçus natifs vérifiés à partir des lignes et du règlement enregistré, partageables par la feuille système.
- Dépenses et bilan de trésorerie des trois métiers en SwiftData local. Ce bilan n'est pas un calcul de bénéfice comptable.
- L'entitlement Sign in with Apple est déclaré dans la cible, mais la validation de la capacité sur le profil Apple **déjà existant** doit être effectuée au moment de compiler. Ne jamais modifier les certificats/profils automatiquement.
- L'historique hybride/Supabase ne migre pas automatiquement vers l'identité locale/Apple. Une migration explicite et testée est nécessaire.
- La compilation macOS et les tests simulateur sont assurés sur GitHub Actions ; l'environnement local Linux vérifie seulement la syntaxe Swift. Voir `PROGRESS_TRACKER.md` pour les dernières révisions certifiées.
