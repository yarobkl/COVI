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
| Identité locale sans mot de passe | 0 % | 81 % | Tests XCTest exécutés, récupération/export de compte |
| Connexion native Apple | 0 % | 68 % | Validation réelle Sign in with Apple et profil déjà provisionné |
| Persistance SwiftData locale | 62 % | 70 % | Migration de schéma, tests de corruption/restauration |
| Répertoire d'établissements iCloud privé | 0 % | 65 % | Tests multi-iPhone, collisions et hors-ligne prolongé |
| Journal CloudKit des renommages / remboursements | 40 % | 48 % | Tests de rejeu et résolution des conflits |
| Synchronisation CloudKit **des données métier** | 5 % | 23 % | Reçus confirmés archivés ; produits, stock, commandes actives, réservations, clients, personnel non synchronisés |
| Multi-appareils propriétaire | 15 % | 52 % | Validation Apple/iCloud, inventaires, activités actives, séparation de comptes |
| Multi-personnel / rôles | 25 % | 30 % | Invitations, identité stable du personnel, permissions |
| Boutique : catalogue | 65 % | 78 % | Catégories, désactivation sûre, tests de parcours iPhone |
| Boutique : stock / balles / inventaire | 64 % | 73 % | Historique complet, valorisation, tests stock concurrents |
| Boutique : caisse / confirmation manuelle | 75 % | 80 % | Tests physiques, coupure réseau, remboursement partiel |
| Boutique : reçus / historique | 28 % | 78 % | Export PDF natif, impression, tests UI |
| Restaurant : salle et tables | 66 % | 78 % | Réservations, flux multi-serveurs, tests iPhone |
| Restaurant : commandes et cuisine | 64 % | 76 % | Annulation / corrections, calculs avancés, tests |
| Restaurant : règlement en caisse | 66 % | 81 % | Reçu imprimable, tests concurrence et double paiement sur appareil |
| Salon : équipe réelle | 5 % | 79 % | Historique des affectations, rôles, tests UI |
| Salon : agenda / rendez-vous | 61 % | 79 % | Plages horaires avancées, rappels et tests iPhone |
| Salon : catalogue / encaissement | 66 % | 73 % | Retour client, modifications, tests de flux |
| Salon : clients / fiches | 65 % | 74 % | Consentements, export, suppression, tests iPhone |
| Salon : rapports / commissions | 55 % | 65 % | Périodes, réconciliation financière, tests |
| Dépenses (trois métiers) | 0 % | 74 % | Rapports de marge, export et partage iCloud à ajouter |
| Trésorerie mensuelle multi-métier | 0 % | 76 % | Recoupement sur appareils, tests UI, export mensuel |
| Paiements externes manuels (sans SDK de paiement) | 65 % | 78 % | Traçabilité du moyen de paiement et reçus réels |
| Sécurité PIN et accès caisse simplifié | 52 % | 76 % | Tests exécutés, parcours d'enrôlement simplifié |
| Aide et accessibilité | 25 % | 30 % | Guide initial, Dynamic Type, VoiceOver, états erreur/vides |
| Conformité aux 46 maquettes | Non vérifiée | Non vérifiée | Maquettes et comparaison sur iPhone indispensables |
| Journal des événements métier local | 30 % | 82 % | Protocole de réplication effectif, purge sécurisée et résolutions de conflits |
| Tests unitaires iOS | 25 % | 78 % | 53/53 XCTest réussis sur la révision de référence ; tests ajoutés ensuite à exécuter |
| Build et tests globaux iOS | 0 % | 70 % | Compilation + 53 XCTest réussis sur macOS ; dernières modifications à revérifier ; tests visuels indisponibles |
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
22. Vérifier la syntaxe des fichiers Swift par analyseur syntaxique (aucune erreur détectée).
23. Ajouter une archive iCloud privée immuable des paiements confirmés, indépendante de l'inventaire.
24. Conserver noms, prix unitaires et montants exacts sur les reçus synchronisés.
25. Détecter les doublons, collisions et divergences de montants lors du rejeu de reçus CloudKit.
26. Empêcher qu'une archive distante modifie le stock ou confirme un paiement non enregistré.
27. Ajouter les tests de sérialisation, réimportation idempotente et isolation inter-établissements.
28. Lier définitivement une identité COVI à son compte iCloud privé pour empêcher un changement de compte silencieux.
29. Journaliser la création de produits, les arrivages, les balles et les ajustements de stock boutique.
30. Journaliser la création des tables, les articles de menu et leur disponibilité au restaurant.
31. Journaliser la création, désactivation et réactivation des collaborateurs du salon.
32. Journaliser les créations, modifications et annulations de rendez-vous et de fiches clients salon.
33. Tracer la réception initiale du stock du salon avec un mouvement comptable.
34. Ajouter des tests de cycle restaurant, doubles règlements et événements métier salon.
35. Rendre les journaux Boutique entièrement transactionnels pour création, arrivages et stock.
36. Journaliser les changements de cartes et de tables restaurant, avec retour arrière sur erreur.
37. Associer chaque rendez-vous salon à un acteur et journaliser sa création.
38. Journaliser la modification du profil client salon et les annulations de rendez-vous.
39. Journaliser l'ajout des prestations, produits et quantités initiales du salon.
40. Ajouter un test du parcours complet restaurant : table, commande, cuisine, règlement, idempotence.
41. Empêcher une identité COVI de réutiliser silencieusement le CloudKit privé d'un autre compte iCloud.
42. Persister la fiche de profil locale SwiftData lors de la connexion native.
43. Remplacer les identifiants UUID affichés au personnel par des noms lisibles.
44. Permettre le changement du nom de profil sans connexion réseau et le tester.
45. Déplacer la déconnexion dans les réglages du compte, pour ne pas encombrer l'écran principal.
46. Ajouter une confirmation explicite avant toute déconnexion.
47. Garder l'état de synchronisation discret et compatible avec les petits écrans.
48. Permettre le choix du moyen de paiement réel à la caisse du restaurant.
49. Exiger le montant d'espèces reçu, avec calcul de la monnaie à rendre.
50. Exiger une confirmation humaine explicite pour chaque règlement Mobile Money au restaurant.
51. Refuser le règlement d'une addition vide et toute tentative de deuxième encaissement.
52. Écrire le moyen de règlement effectif et le montant reçu sur le paiement du restaurant.
53. Ajouter des tests pour les espèces insuffisantes, les paiements mobiles non confirmés et les additions vides.
54. Vérifier les détails immuables des reçus iCloud lors de leur réconciliation (libellés, acteurs, périodes, sommes encaissées).
55. Ajouter des tests de divergence entre reçus locaux et reçus déjà archivés.
56. Exécuter pour la première fois l'app et les XCTest en véritable Xcode macOS distant, sans code signing.
57. Isoler la cause des 28 échecs de tests du simulateur : Keychain refuse les opérations sans entitlement (`-34018`).
58. Introduire une abstraction de stockage sécurisé injectable, conservant Keychain dans la production iOS.
59. Remplacer uniquement le stockage des tests par une implémentation mémoire déterministe.
60. Ajouter des scénarios d'échec du stockage sécurisé prouvant que le propriétaire et la session restent bloqués si la clé est inaccessible.
61. Corriger le rafraîchissement de la session PIN pour utiliser la même horloge que les vérifications d'inactivité.
62. Tester précisément la prolongation de session et l'expiration après deux minutes.
63. Permettre au propriétaire de gérer son établissement sans avoir à créer un second code maître.
64. Maintenir la vérification du code maître lorsqu'il a été volontairement configuré.
65. Refuser toute modification sensible lorsque la lecture du stockage sécurisé est indisponible.
66. Distinguer la confirmation d'un remboursement réellement remis de tout paiement automatisé.
67. Ajouter l'édition native des noms et des prix des produits boutique.
68. Refuser les articles dupliqués dans un même établissement (casse et espaces ignorés).
69. Interdire la modification d'un article appartenant à une autre boutique.
70. Conserver les libellés et prix historiques sur les tickets déjà encaissés après modification du catalogue.
71. Journaliser les mises à jour de catalogue de manière transactionnelle.
72. Ajouter des tests pour les changements de prix, les doublons et le cloisonnement des établissements.
73. Afficher les remboursements manuellement confirmés sur les reçus natifs.
74. Conserver l'encaissement d'origine visible même si un remboursement intégral est enregistré.
75. Ajouter la mention de remboursement aux reçus partagés par le système iOS.
76. Vérifier le rattachement du remboursement au bon paiement, propriétaire et établissement.
77. Ajouter des tests de reçu remboursé et de remboursement provenant d'un autre propriétaire.
78. Exiger la confirmation humaine au niveau du service métier salon avant tout encaissement.
79. Tester qu'un paiement salon non confirmé ne touche ni le stock ni les enregistrements de caisse.
80. Ajouter la recherche native de clients salon par nom et téléphone.
81. Afficher des états vides explicites lorsque le salon n'a aucun client ou aucune correspondance.
82. Demander confirmation avant d'annuler un rendez-vous, en conservant son historique.
83. Tester la libération du créneau après annulation et interdire l'annulation d'un rendez-vous encaissé.
84. Ajouter l'édition native des plats, boissons, catégories et prix du restaurant.
85. Protéger les tickets déjà envoyés en cuisine lorsque les prix de la carte changent.
86. Ajouter un test restaurant de mise à jour de menu et de conservation du ticket historique.
87. Ajouter l'édition du nom et de la capacité des tables de restaurant lorsqu'elles sont libres.
88. Bloquer la modification des tables occupées et empêcher les noms de table dupliqués.
89. Vérifier par XCTest que le restaurant interdit le règlement tant que les plats ne sont pas servis.
90. Vérifier par XCTest qu'un plat en rupture ne peut pas être envoyé et qu'aucun ajout n'est possible après l'addition.
91. Obtenir une compilation iOS native sans signature réussie sur un hôte macOS Xcode.
92. Obtenir une exécution complète de 53 XCTest sur simulateur avec zéro échec, zéro code de distribution.
93. Recenser les 23 catégories réelles de dépenses existantes dans la version web COVI.
94. Créer un modèle SwiftData natif pour les dépenses avec montant entier, acteur, catégorie, date et note.
95. Mettre à disposition la saisie des dépenses pour propriétaires et responsables des trois métiers.
96. Construire un journal des dépenses par mois avec total et états vides.
97. Permettre l'annulation non destructive d'une dépense par le propriétaire, en conservant une trace d'audit.
98. Journaliser la saisie et l'annulation de dépense dans l'outbox transactionnelle.
99. Ajouter des tests pour les montants invalides, le cloisonnement, le refus d'annulation non autorisée et l'idempotence.
100. Ajouter un tableau de trésorerie natif utilisable par les trois métiers.
101. Basculer le calcul du chiffre d'affaires sur les paiements réellement confirmés plutôt que les commandes seulement ouvertes.
102. Déduire les remboursements réels et les dépenses actives du mois sélectionné.
103. Regrouper les entrées par moyen de paiement et les sorties par catégorie.
104. Éviter de présenter ce solde net comme un bénéfice comptable ou un solde bancaire.
105. Vérifier la séparation stricte entre établissements et périodes dans les statistiques.
106. Ajouter des tests de calcul et d'exclusion des dépenses annulées.
107. Analyser le diagnostic Xcode de la carte restaurant et corriger la collision entre erreur attrapée et état d'interface.
108. Corriger le même risque d'ombre portée sur les écrans de dépenses ajoutés dans ce lot.

## Vérification macOS sans signature (branche de diagnostic uniquement)

Le workflow GitHub Actions `COVI Native iOS Diagnostics` s'exécute sur la branche
`wip/covi-native-20261119-no-testflight`, distincte de la branche Xcode Cloud.
Le second lancement a **compilé l'app et ses tests avec succès** (`build-for-testing`, étape 6).
Il a ensuite exécuté 46 XCTest : 18 réussis, 28 en échec, **dont les erreurs sont toutes liées à
l'accès Keychain non signé** (`OSStatus -34018`, ou refus de caisse qui en découle).
La signature étant volontairement interdite, le stockage sécurisé a été rendu injectable,
avec Keychain inchangé en production et un stockage isolé en mémoire dans les XCTest.
Le troisième lancement de référence (`765f157`, action `44473901012`) a ensuite
**réussi la compilation et les 53 XCTest** sans aucune erreur. Les modifications
des lots Boutique / Salon / Restaurant ajoutées après cette révision nécessitent
un nouveau lancement : leurs tests ne sont pas encore comptés comme exécutés.
Un quatrième lancement (`b0944ac`) a permis de trouver, au compilateur, deux
affectations ambiguës dans le nouvel éditeur restaurant ; elles ont été corrigées
avant le lancement du lot incluant également dépenses et trésorerie.
Ce contrôle ne crée **ni archive de distribution ni provisioning**, et ne valide pas les maquettes.

## Limites bloquantes

- Une connexion Apple et un compte iCloud ne prouvent **pas** à eux seuls la synchronisation complète :
  les données métiers restent locales tant qu'un protocole de réplication testé n'est pas en place.
- Les anciens utilisateurs Supabase/Capacitor nécessitent un protocole de migration explicite.
- Les sources des 46 maquettes approuvées ne figurent pas dans ce checkout.
- Aucune archive iOS, aucun fichier de signature ni aucun profil de provisioning n'a été créé ou modifié.
- Aucun push n'a été effectué vers la branche reliée à Xcode Cloud.
