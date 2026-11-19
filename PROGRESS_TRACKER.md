# COVI — progression iOS native

Dernier audit : 19 novembre 2026 — dépôt `yarobkl/COVI`, branche `feature/covi-native-swiftui-cloud`.

Le checkout a été reconstruit depuis le dernier commit distant `acd3f383`.
Les changements non publiés du précédent environnement ne figuraient **pas** dans GitHub.
Ce tableau repart donc de l'état **vérifié du code distant**, pas des anciens pourcentages annoncés.

## Critère de notation

- 0 % : absent ; 25 % : squelette ; 50 % : parcours principal partiel ; 70 % : utilisable sur cas normal ;
  90 % : parcours complet, erreurs, états vides et tests compilés ; 100 % : vérifié sur iPhone contre les maquettes.
- **Aucun module ne peut obtenir 90 % sans compilation iOS et tests sur simulateur/iPhone.**
- L'outil Xcode/Swift n'est pas installé dans cet environnement Linux. L'analyse syntaxique Swift a été exécutée
  avec tree-sitter, **ce qui n'est pas une compilation ni une exécution XCTest**.

| Module | Initial distant | Actuel, estimé | Ce qui reste avant 90 % |
| --- | ---: | ---: | --- |
| Coque iOS SwiftUI / navigation | 65 % | 72 % | Validation visuelle iPhone/iPad, tests VoiceOver |
| Accueil et parcours de première ouverture | 55 % | 68 % | Comparaison des 46 écrans approuvés, animations |
| Identité locale sans mot de passe | 0 % | 78 % | Tests XCTest exécutés, récupération/export de compte |
| Connexion native Apple | 0 % | 68 % | Validation réelle Sign in with Apple et profil déjà provisionné |
| Persistance SwiftData locale | 62 % | 70 % | Migration de schéma, tests de corruption/restauration |
| Répertoire d'établissements iCloud privé | 0 % | 65 % | Tests multi-iPhone, collisions et hors-ligne prolongé |
| Journal CloudKit des renommages / remboursements | 40 % | 48 % | Tests de rejeu et résolution des conflits |
| Synchronisation CloudKit **des données métier** | 5 % | 5 % | Produits, stock, commandes, réservations, clients, personnel : non synchronisés |
| Multi-appareils propriétaire | 15 % | 45 % | Validation Apple/iCloud, données métier, séparation de comptes |
| Multi-personnel / rôles | 25 % | 30 % | Invitations, identité stable du personnel, permissions |
| Boutique : catalogue | 65 % | 68 % | Édition, catégories, suppression contrôlée, tests |
| Boutique : stock / balles / inventaire | 64 % | 70 % | Historique complet, valorisation, tests stock concurrents |
| Boutique : caisse / confirmation manuelle | 75 % | 80 % | Tests physiques, coupure réseau, remboursement partiel |
| Boutique : reçus / historique | 28 % | 73 % | Export PDF natif, impression, tests UI |
| Restaurant : salle et tables | 66 % | 71 % | Réservations, flux multi-serveurs, tests |
| Restaurant : commandes et cuisine | 64 % | 70 % | Annulation / corrections, calculs avancés, tests |
| Restaurant : règlement en caisse | 66 % | 73 % | Reçu imprimable, tests concurrence et double paiement |
| Salon : équipe réelle | 5 % | 77 % | Historique des affectations, rôles, tests UI |
| Salon : agenda / rendez-vous | 61 % | 72 % | Gestion annulations, plages horaires, rappels |
| Salon : catalogue / encaissement | 66 % | 73 % | Retour client, modifications, tests de flux |
| Salon : clients / fiches | 65 % | 66 % | Recherche, consentements, export, suppression |
| Salon : rapports / commissions | 55 % | 65 % | Périodes, réconciliation financière, tests |
| Paiements externes manuels (sans SDK de paiement) | 65 % | 78 % | Traçabilité du moyen de paiement et reçus réels |
| Sécurité PIN et accès caisse simplifié | 52 % | 76 % | Tests exécutés, parcours d'enrôlement simplifié |
| Aide et accessibilité | 25 % | 30 % | Guide initial, Dynamic Type, VoiceOver, états erreur/vides |
| Conformité aux 46 maquettes | Non vérifiée | Non vérifiée | Maquettes et comparaison sur iPhone indispensables |
| Tests unitaires iOS | 25 % | 47 % | Compilation et exécution réelles de toute la suite |
| Build et tests globaux iOS | 0 % | 0 % | Compilation macOS Xcode sans déclencher TestFlight |
| Livraison TestFlight | En pause | En pause | Aucune action autorisée dans ce lot |

## Changements réellement effectués dans ce lot

1. Restaurer un checkout indépendant du dépôt GitHub d'origine, sans modifier la branche distante.
2. Auditer les instructions de dépôt, schémas, écrans SwiftUI et points d'accès réseau.
3. Remplacer la dépendance Supabase Auth par une session Apple et une identité locale en Keychain.
4. Ajouter le bouton système Sign in with Apple et le contrôle de validité des identifiants restaurés.
5. Fournir un parcours local sans email, mot de passe ni abonnement.
6. Conserver les identifiants locaux entre lancements et éviter l'effacement des données au logout.
7. Supprimer les paramètres Supabase, la vitrine web et les appels REST de la cible iOS.
8. Remplacer la vitrine externe par une fiche native exportable via partage système et QR hors-ligne.
9. Ajouter un répertoire d'établissements privé CloudKit avec fusion prudente et limite 3.
10. Récupérer les établissements après connexion Apple sur un second appareil.
11. Afficher l'état de chargement, l'erreur iCloud et une action de relance.
12. Autoriser la caisse propriétaire sans PIN initial, et imposer le PIN une fois configuré.
13. Fermer la caisse en cas d'erreur Keychain ; valider les quatre chiffres ASCII.
14. Corriger le risque de double décrément de stock par articles dupliqués.
15. Remplacer les collaborateurs fictifs du salon par des fiches SwiftData administrables.
16. Brancher le vrai personnel sur l'agenda, les rendez-vous et les encaissements salon.
17. Préserver l'historique après désactivation d'un collaborateur.
18. Prendre en charge Airtel, MTN, Orange, Moov et espèces avec confirmation en caisse.
19. Construire des reçus natifs vérifiant le total, la remise et les paiements.
20. Brancher le partage des reçus en boutique, restaurant et salon.
21. Ajouter des tests de session, fusion CloudKit, stock, caisse, salon et reçus.
22. Vérifier la syntaxe des 36 fichiers Swift par analyseur syntaxique (aucune erreur détectée).

## Limites bloquantes

- Une connexion Apple et un compte iCloud ne prouvent **pas** à eux seuls la synchronisation complète :
  les données métiers restent locales tant qu'un protocole de réplication testé n'est pas en place.
- Les anciens utilisateurs Supabase/Capacitor nécessitent un protocole de migration explicite.
- Les sources des 46 maquettes approuvées ne figurent pas dans ce checkout.
- Aucune archive iOS, aucun fichier de signature ni aucun profil de provisioning n'a été créé ou modifié.
- Aucun push n'a été effectué vers la branche reliée à Xcode Cloud.
