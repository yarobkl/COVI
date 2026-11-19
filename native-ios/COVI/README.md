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
La révision `2d7e912` a réussi **109 XCTest sur 109**, avec les 12 tests
des miroirs opérationnels, sur simulateur iOS via le workflow macOS
`44501925643`. La suite doit également être validée sur deux appareils réels.

## État réel
- SwiftUI et SwiftData locaux pour Boutique, Restaurant et Salon ; aucune WebView ni API Supabase.
- Identité locale en Keychain ou Sign in with Apple (identifiant stable entre appareils).
- CloudKit privé : répertoire d'établissements, journal des **renommages et remboursements**, archive immuable des reçus, dépenses avec annulations idempotentes, ainsi que nouveaux miroirs des articles, mouvements de stock, balles, commandes et cuisine, tables, rendez-vous, équipe, clients et commissions.
- Les données métier ont une réplication explicite en développement : compare-and-swap côté CloudKit, mémorisation de la dernière version distante, refus d'écraser les modifications hors-ligne concurrentes, conservation du journal immuable et rejet d'un stock négatif. **La validation multi-iPhone en conditions réelles reste à faire.**
- Pour le moment, les zones sont **privées au compte iCloud du propriétaire** : un employé utilisant son propre identifiant Apple ne reçoit pas automatiquement ces données. Le partage CloudKit entre comptes et les invitations nécessitent une implémentation et une validation distinctes.
- La caisse est accessible sans PIN au propriétaire qui n'a pas installé de code ; le personnel et les propriétaires ayant configuré un code passent par un verrou local.
- Réception de paiements en caisse uniquement. COVI n'encaisse pas de monnaie électronique.
- Reçus natifs vérifiés à partir des lignes et du règlement enregistré, partageables par la feuille système.
- Dépenses et bilan de trésorerie des trois métiers en SwiftData local. Ce bilan n'est pas un calcul de bénéfice comptable.
- L'entitlement Sign in with Apple est déclaré dans la cible, mais la validation de la capacité sur le profil Apple **déjà existant** doit être effectuée au moment de compiler. Ne jamais modifier les certificats/profils automatiquement.
- L'historique hybride/Supabase ne migre pas automatiquement vers l'identité locale/Apple. Une migration explicite et testée est nécessaire.
- La compilation macOS et les tests simulateur sont assurés sur GitHub Actions ; l'environnement local Linux vérifie seulement la syntaxe Swift. Voir `PROGRESS_TRACKER.md` pour les dernières révisions certifiées.

## Fonctionnement des données sur deux iPhone

1. Se connecter avec **la même identité Apple dans COVI** et **le même compte iCloud** sur les deux appareils.
2. Créer ou ouvrir les mêmes établissements grâce au répertoire iCloud privé.
3. Les modèles restent dans SwiftData sur chaque iPhone ; quand COVI est ouvert au premier plan, les changements CloudKit sont vérifiés à intervalle d'environ **60 secondes**, sans serveur tiers et sans transfert depuis Supabase.
4. Une coupure réseau conserve les écritures locales. Au retour, les journaux immuables sont rejoués et les états éditables sont comparés à leur dernière version distante. Si deux modifications sont incompatibles, la synchronisation s'arrête sur un **conflit visible**, sans écraser silencieusement les données.
5. Un règlement reste **confirmé humainement en caisse** ; la synchronisation ne doit jamais transformer une commande ouverte en paiement validé. Seul le reçu vérifié peut fermer la vente distante.

Avant toute livraison, vérifier sur deux iPhone les scénarios de caisse hors-ligne, stock concurrent, cuisine, agenda et dépenses ; déployer le schéma CloudKit exigé par les nouveaux types de records et contrôler les capacités Apple existantes, **sans créer ni modifier de certificat ou profil**. Les tests simulateur n'exercent pas un vrai compte iCloud.
