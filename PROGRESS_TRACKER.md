# COVI — progression iOS native

## Reprise COVI 2.0 — 25 novembre 2026

Branche active de refonte `feature/covi-2-native`, contrat produit dans
`native-ios/COVI_2_PRODUCT_SPEC.md`. Les chiffres historiques ci-dessous
décrivent la base native du 19 novembre et ne mesurent pas la réalisation de COVI 2.0.

### Validation du dernier lot

- Révision vérifiée `10e3f27`, publiée le 25 novembre 2026 à 19 h 41 (Europe/Paris).
- Correction `36ffdeb` limitant le déverrouillage de caisse au collaborateur et à son établissement.
- Régressions `f2554f1` pour le propriétaire et le caissier entre établissements.
- Action macOS https://github.com/yarobkl/COVI/actions/runs/45677679183, job `139429474448`.
- Compilation de l'application et des tests réussie. Journaux XCTest vérifiés :
  **115 tests exécutés, 0 échec**, dont 13 tests PIN.
- Capture de l'accueil iPhone produite par le workflow. Comparaison aux maquettes encore à effectuer.
- Cette exécution sur simulateur ne valide pas les migrations de données existantes,
  le partage entre comptes Apple ni la synchronisation sur deux appareils physiques.

### Compatibilité SwiftData

- Révision `53ada6e` : compilation et **116 XCTest réussis, 0 échec** sur le simulateur iOS ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45696516004)).
- Le nouveau test vérifie sur disque la conservation de l'établissement, du stock et du mouvement associé après réouverture.
- La comparaison avec la base native `81dc85a` confirme que les modèles, leur liste dans le schéma et la configuration du stockage par défaut sont identiques.
- La validation d'une mise à niveau depuis une ancienne version installée nécessite encore une base de cette version. La recette CloudKit sur deux iPhone signés est décrite dans `native-ios/CLOUDKIT_VALIDATION.md`.

### Lot 2 — Contrôle local des droits

- La sélection des établissements et les opérations métier utilisent la même
  résolution des rôles locaux. Les encaissements boutique et salon exigent une
  adhésion active pour les collaborateurs, en plus du déverrouillage PIN.
- Le service restaurant relit le rôle enregistré à chaque opération. Un écran
  resté ouvert après un changement de rôle perd ses anciens droits à l’écriture.
- Deux tests couvrent la désactivation d’un caissier dont le PIN est déverrouillé
  et le changement de rôle dans le service restaurant. Sur `9933b51`, la
  compilation de l’application et l’étape XCTest sur simulateur iPhone ont
  réussi ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45699387443)).
- Le lot reste en cours. La liaison Apple/Google, les invitations, les sessions
  révocables entre appareils et leurs contrôles serveur nécessitent encore une
  autorité côté serveur. Les règles locales s’appliquent dès réception du
  changement de rôle ou de la désactivation sur l’appareil.

### Backend du lot 2 et TestFlight

- Le propriétaire autorise le choix et la mise en place du backend, ainsi que la livraison TestFlight après validation.
- Supabase Auth et PostgreSQL sont retenus pour la préproduction native. La migration `native-ios/backend/migrations/20261125220000_team_authority.sql` introduit un schéma privé et une résolution serveur des rôles tenant compte des révocations. La migration reste à exécuter et à tester. Le projet historique COVI est inactif.
- Les flux Apple/Google, invitations et sessions restent à implémenter en préservant les établissements existants.
- Le profil de distribution corrigé a permis de signer et livrer la bêta technique 1.0.13 (10051), basée sur `6eb37ed` ([exécution signée](https://github.com/yarobkl/COVI/actions/runs/45706005104)). L’envoi de la refonte COVI 2.0 reste soumis à sa validation visuelle et fonctionnelle.

### Lot 3 — Parcours d’entrée

- L’accueil, la connexion et la création de compte s’adaptent aux grandes tailles de texte. Les formulaires restent centrés sur iPad et les boutons peuvent grandir quand leur libellé revient à la ligne.
- Diagnostics iOS réussis sur [`0b5230d`](https://github.com/yarobkl/COVI/actions/runs/45709003559), [`cd553ef`](https://github.com/yarobkl/COVI/actions/runs/45709647192) et [`aaebcf1`](https://github.com/yarobkl/COVI/actions/runs/45709858546).
- Comparaison de la capture d’accueil d’`aaebcf1` à la planche `5AD6CB67`. Les trois métiers, les titres et les deux actions sont visibles. Les écarts constatés portent sur la flèche placée avant « Commencer », le fond plat et la coupure sous la photo.
- L’accueil réutilise désormais le fond de marque, place la flèche après « Commencer » et fond le bord inférieur de la photo. Les deux actions restent accessibles sous le contenu défilant. Sur [`1c40f85`](https://github.com/yarobkl/COVI/actions/runs/45714877928), 118 XCTest réussis. La capture du simulateur iPhone comparée à la planche confirme la flèche à droite, le fond champagne et le fondu sous la photo. La forme du motif et l’espace entre la photo et les boutons diffèrent encore de la planche. Le rendu aux grandes tailles de texte et sur les appareils physiques reste à contrôler.
- Les planches retrouvées ont été relues et leurs intitulés corrigés dans `native-ios/DESIGN_REFERENCE_MAP.md`. La planche Boutique `9BF220F7` montre Accueil, Vendre et Encaissement. Le parcours Vendre doit garder le panier en haut après la recherche et le total avec son action au bas de l’écran.

### Lot 3 — Boutique

- La planche `9BF220F7` a été inspectée. Sur Vendre, le panier apparaît dans
  une carte juste sous la recherche, au-dessus du catalogue. L’action
  d’encaissement reste au bas de l’écran. Le bandeau qui répétait le titre
  de navigation a été retiré.
- Révision [`4fb3a77`](https://github.com/yarobkl/COVI/commit/4fb3a77589e324c97f2fc37e39cf5c704dbdb66b),
  [compilation et étape XCTest réussies](https://github.com/yarobkl/COVI/actions/runs/45715459342).
  Les photos du catalogue et le raccourci scan suivent leur lot métier.
- Les captures de `87232c4` ont été comparées à la planche `9BF220F7`
  ([images GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45722744021/artifacts/15073282735)).
  Vendre affiche le panier sous la recherche et le total fixe de 35 000 FCFA.
  En espèces, la feuille affiche un montant reçu de 40 000 FCFA et une monnaie de
  5 000 FCFA. La commande de confirmation était sous la zone visible.
- La confirmation reste maintenant visible au bas de la feuille pendant le
  défilement. Sur `cf61665`, Debug, 118 XCTest et Release ont réussi ([diagnostics](https://github.com/yarobkl/COVI/actions/runs/45724727588)).
  [La capture](https://github.com/yarobkl/COVI/actions/runs/45724727588/artifacts/15073324402) confirme le bouton visible dès l’ouverture. Les champs « Montant reçu » et « Monnaie à rendre » nécessitent encore un défilement avec la liste complète des moyens de paiement. L’en-tête de
  l’établissement est hors cadrage des captures isolées. La couverture
  iPad, grandes tailles de texte et iPhone physique reste à vérifier.

- Le commit `87232c4` regroupe les cartes du panier et de l’encaissement
  et ajoute des scénarios de capture avec des données synthétiques en mémoire.
  GitHub Actions a validé Debug, 118 XCTest et Release sur simulateur
  ([diagnostics](https://github.com/yarobkl/COVI/actions/runs/45722744021)).
- Le panier et la caisse partagent désormais le calcul contrôlé du sous-total.
  Un résultat hors limites affiche « Montant invalide » dans le panier et
  bloque l’encaissement. Le test de dépassement couvre aussi ce calcul.
  L’état sélectionné du moyen de paiement est annoncé par VoiceOver.

### Suite du lot 1

Le correctif d’annulation CloudKit `0872560` a également passé la compilation
et l’étape XCTest sur simulateur ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45698668245)).

Auditer la migration SwiftData et les conflits de synchronisation selon le contrat
COVI 2.0, puis ajouter les régressions nécessaires avant les changements d'identité
et d'équipes. Les invitations multi-comptes et le QR restaurant demandent encore
une décision de backend. La conformité visuelle nécessite les références originales.
Le passage TestFlight reste soumis aux validations prévues dans le contrat produit.


Dernier audit : 19 novembre 2026 — dépôt `yarobkl/COVI`, branche source
`feature/covi-native-swiftui-cloud` laissée intacte ; travail isolé sur
`wip/covi-native-20261119-no-testflight` (diagnostic distant).

Le checkout a été reconstruit depuis le dernier commit distant `acd3f383`.
Les changements non publiés du précédent environnement ne figuraient **pas** dans GitHub.
Ce tableau repart donc de l'état **vérifié du code distant**, pas des anciens pourcentages annoncés.

## Critère de notation

- 0 % : absent ; 25 % : squelette ; 50 % : parcours principal partiel ; 70 % : utilisable sur cas normal ;
  90 % : parcours complet, erreurs, états vides et tests compilés ; 100 % : vérifié sur iPhone contre les maquettes.
- **Aucun module ne peut obtenir 90 % sans compilation iOS et tests sur simulateur/iPhone.**
- L'outil Xcode/Swift n'est pas installé dans cet environnement Linux. L'analyse syntaxique locale
  ne remplace pas une compilation ; **les compilations et XCTest réels sont assurés par le workflow
  macOS distinct, sans signature**, détaillé en fin de document.

| Module | Initial distant | Actuel, estimé | Ce qui reste avant 90 % |
| --- | ---: | ---: | --- |
| Coque iOS SwiftUI / navigation | 65 % | 72 % | Validation visuelle iPhone/iPad, tests VoiceOver |
| Accueil et parcours de première ouverture | 55 % | 70 % | Comparaison des 46 écrans approuvés, animations |
| Identité locale sans mot de passe | 0 % | 81 % | Tests XCTest exécutés, récupération/export de compte |
| Connexion native Apple | 0 % | 68 % | Validation réelle Sign in with Apple et profil déjà provisionné |
| Persistance SwiftData locale | 62 % | 70 % | Migration de schéma, tests de corruption/restauration |
| Répertoire d'établissements iCloud privé | 0 % | 65 % | Tests multi-iPhone, collisions et hors-ligne prolongé |
| Journal CloudKit des renommages / remboursements | 40 % | 48 % | Tests de rejeu et résolution des conflits |
| Synchronisation CloudKit **des données métier** | 5 % | 72 % | Schéma préparé en développement dans la console Apple ; pas déployé en production, tests physiques et partage inter-comptes encore nécessaires |
| Multi-appareils propriétaire | 15 % | 74 % | XCTest supplémentaires de convergence et conflits indépendants ; CloudKit réel sur deux iPhone non testé |
| Multi-personnel / rôles | 25 % | 30 % | Invitations, identité stable du personnel, permissions |
| Boutique : catalogue | 65 % | 81 % | Catégories, tests d'usage sur iPhone, synchronisation catalogue |
| Boutique : stock / balles / inventaire | 64 % | 83 % | Historique complet, coût de revient, tests de stock concurrents |
| Boutique : caisse / confirmation manuelle | 75 % | 81 % | Tests physiques, coupure réseau, remboursement partiel |
| Boutique : reçus / historique | 28 % | 84 % | Impression système et tests UI sur iPhone |
| Restaurant : salle et tables | 66 % | 78 % | Réservations, flux multi-serveurs, tests iPhone |
| Restaurant : commandes et cuisine | 64 % | 76 % | Annulation / corrections, calculs avancés, tests |
| Restaurant : règlement en caisse | 66 % | 82 % | Reçu imprimable, tests concurrence et double paiement sur appareil |
| Salon : équipe réelle | 5 % | 79 % | Historique des affectations, rôles, tests UI |
| Salon : agenda / rendez-vous | 61 % | 83 % | Plages horaires avancées, rappels et tests iPhone |
| Salon : catalogue / encaissement | 66 % | 83 % | Corrections et retours avancés, tests multi-iPhone et synchronisation catalogue |
| Salon : clients / fiches | 65 % | 79 % | Consentements, export, suppression, tests iPhone |
| Salon : rapports / commissions | 55 % | 65 % | Périodes, réconciliation financière, tests |
| Dépenses (trois métiers) | 0 % | 82 % | Tests réels multi-iPhone, confidentialité des exports et rapports de marge à ajouter |
| Trésorerie mensuelle multi-métier | 0 % | 79 % | Recoupement sur appareils, tests UI, contrôle des fichiers CSV exportés |
| Paiements externes manuels (sans SDK de paiement) | 65 % | 78 % | Traçabilité du moyen de paiement et reçus réels |
| Sécurité PIN et accès caisse simplifié | 52 % | 76 % | Tests exécutés, parcours d'enrôlement simplifié |
| Aide et accessibilité | 25 % | 30 % | Guide initial, Dynamic Type, VoiceOver, états erreur/vides |
| Conformité aux 46 maquettes | Non vérifiée | Non vérifiée | Maquettes et comparaison sur iPhone indispensables |
| Journal des événements métier local | 30 % | 82 % | Protocole de réplication effectif, purge sécurisée et résolutions de conflits |
| Tests unitaires iOS | 25 % | 90 % | 113/113 XCTest réussis sur `4f037fe` ; parcours physiques et validations CloudKit multi-appareils encore nécessaires |
| Build et tests globaux iOS | 0 % | 86 % | Compilation + 113 XCTest réussis sur macOS sans signature ; tests visuels indisponibles |
| Livraison TestFlight native | En pause | 45 % | Le préflight réel a refusé le profil App Store existant : il ne contient pas les entitlements CloudKit. Archive, schéma Production et traitement Apple restent bloqués ; aucune signature modifiée |

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
109. Mettre à jour la documentation Xcode pour ouvrir le vrai projet plutôt que recréer un template.
110. Expliquer clairement le mode de diagnostic sans signature ni distribution TestFlight.
111. Ajouter une aide intégrée pour la saisie des dépenses et la lecture du bilan financier.
112. Renforcer les droits d'enregistrement des dépenses : propriétaire ou responsable actif seulement.
113. Ajouter des tests de refus pour les caissiers et les responsables désactivés.
114. Permettre la correction native du nom du client salon sans perdre son historique.
115. Contrôler la longueur des noms, téléphones, notes et préférences avant enregistrement.
116. Tester la modification de fiche client et son journal d'audit.
117. Ajouter les messages d'état vide au catalogue boutique et aux recherches sans résultat.
118. Expliquer clairement l'absence de plats disponibles dans l'éditeur de commande du restaurant.
119. Afficher l'état « aucune commande » dans la cuisine sans laisser un écran vide.
120. Guider le salon lorsque l'équipe, les clients ou le catalogue n'ont pas encore été configurés.
121. Générer un PDF de reçu directement sur l'iPhone avec le moteur PDF natif Apple.
122. Paginer les lignes longues du reçu sans WebView ni bibliothèque externe.
123. Rendre le PDF disponible dans la feuille de partage iOS.
124. Conserver la mention des remboursements dans le PDF partagé.
125. Ajouter un XCTest ouvrant le document PDF avec PDFKit et vérifiant son contenu.
126. Retirer le faux QR de table qui n'effectuait aucune vraie commande native et pouvait troubler le personnel.
127. Remplacer le sélecteur de boutique inutile par un titre simple lorsque le propriétaire n'a qu'un établissement.
128. Réaffirmer la règle produit validée : trois établissements actifs maximum par propriétaire.
129. Unifier cette limite entre l'accueil local, la création SwiftData et le répertoire privé iCloud.
130. Autoriser à nouveau la création après archivage d'un établissement, sans supprimer l'historique.
131. Ajouter un test de la limite multi-établissements et de l'isolation entre propriétaires.
132. Introduire la synchronisation des dépenses entre appareils via CloudKit privé Apple.
133. Répliquer la création d'une dépense comme un fait immuable, sans service web externe.
134. Répliquer séparément son annulation, en conservant la preuve de l'opération initiale.
135. Définir des identifiants déterministes pour rendre le rejeu des annulations idempotent.
136. Gérer les événements CloudKit reçus dans le désordre, grâce à une file locale d'annulations en attente.
137. Refuser les montants, propriétaires, établissements ou contenus contradictoires entre appareils.
138. Lier les marqueurs de dépenses au même compte iCloud privé et conserver un jeton de reprise par établissement.
139. Ajouter des tests de réimportation, désordre des événements, isolation et déterminisme des identifiants.
140. Documenter honnêtement la portée du CloudKit actuel : dépenses et reçus oui, stock et rendez-vous pas encore.
141. Canoniser l'encodage JSON des faits de dépenses pour limiter les divergences de rejeu multi-appareils.
142. Refuser la propagation d'une annulation de dépense émise par une identité autre que le propriétaire.
143. Ajouter un test de rejet des annulations iCloud sans auteur légitime.
144. Signaler à l'utilisateur les annulations de dépenses encore en attente de leur événement d'origine.
145. Ajouter un écran natif d'état des stocks à la boutique.
146. Distinguer quantitativement stock physique, quantités réservées et unités disponibles.
147. Calculer la valeur disponible au prix de vente sans la présenter comme un bénéfice.
148. Signaler les articles faibles et les inventaires incohérents sans fausser les totaux.
149. Ajouter des tests de valorisation, stocks réservés, anomalies et isolation des autres boutiques.
150. Ajouter le changement de créneau d'un rendez-vous salon sans effacer l'historique de réservation.
151. Vérifier les conflits à la fois du client et du collaborateur lors du changement de rendez-vous.
152. Bloquer la modification des rendez-vous annulés ou déjà encaissés.
153. Ajouter un formulaire SwiftUI natif pour déplacer les rendez-vous depuis l'agenda.
154. Préserver le journal métier de modification et l'identifiant stable du rendez-vous.
155. Tester le déplacement, la libération de l'ancien créneau, les collisions et l'accès inter-établissements.
156. Permettre la suspension temporaire des ventes d'un article boutique sans suppression.
157. Préserver les ventes et les mouvements de stock historiques lors de sa désactivation.
158. Interdire toute nouvelle vente d'un article suspendu, même si le panier existait déjà.
159. Permettre la réactivation du catalogue sans recréation ni doublon d'article.
160. Rendre visibles les références suspendues à l'inventaire mais les masquer de la caisse.
161. Journaliser et tester la suspension, la réactivation et l'idempotence des changements d'état.
162. Vérifier que les alertes de stock faible ignorent les références volontairement suspendues.
163. Concevoir un export CSV local iOS ouvrable dans Fichiers, sans service distant.
164. Sérialiser de façon déterministe les colonnes et les lignes de CSV en UTF-8.
165. Échapper correctement les virgules, guillemets et retours à la ligne du contenu.
166. Réduire les risques d'injection de formules dans les tableurs lors d'un export des libellés saisis.
167. Exporter le stock de la seule boutique active, avec ses identifiants et libellés.
168. Inclure le stock physique, les réservations, les disponibilités et les articles suspendus.
169. Exporter le journal mensuel des dépenses avec notes et événements annulés conservés.
170. Ajouter une mise en garde explicite avant la sauvegarde d'un journal pouvant contenir des notes privées.
171. Exporter le bilan financier mensuel dans un tableau CSV cohérent et lisible.
172. Séparer les encaissements, les remboursements, les dépenses et le solde net des flux.
173. Inclure les ventilations par moyen de paiement et catégorie de dépense.
174. Ajouter des tests CSV pour les citations, injections de formules et montants négatifs.
175. Tester l'isolation inter-boutiques lors de l'export des stocks.
176. Tester les exports des dépenses annulées et les agrégats de trésorerie.
177. Centraliser la création de prestations et produits du salon dans un service métier transactionnel.
178. Valider noms, prix, nature de service et niveaux de commission avant création.
179. Interdire les références dupliquées sans distinction de casse ou d'accents.
180. Refuser la modification du catalogue provenant d'un salon différent.
181. Vérifier la commission entre 0 et 100 % pour chaque référence.
182. Distinguer le stock initial des produits physiques et les prestations sans inventaire.
183. Conserver le premier mouvement de stock et sa piste d'audit à la création du produit.
184. Permettre la modification des noms et des prix du catalogue depuis une fiche native.
185. Garder le nom et le prix d'origine sur les tickets déjà encaissés après modification du catalogue.
186. Permettre la correction du taux de commission pour les futures ventes sans réécrire les commissions passées.
187. Conserver l'identifiant du service sur les rendez-vous antérieurs lors d'une édition.
188. Permettre la suspension temporaire d'une prestation ou d'un produit salon sans suppression.
189. Réactiver une référence avec le même identifiant et le même historique.
190. Interdire les nouvelles réservations de prestations suspendues.
191. Interdire l'encaissement direct des références suspendues au niveau du service métier.
192. Préserver la possibilité d'encaisser une prestation déjà réservée avant sa suspension.
193. Afficher la disponibilité dans le catalogue et retirer les références suspendues des sélecteurs de réservation.
194. Ajouter une fiche SwiftUI pour les modifications et la disponibilité des prestations et produits.
195. Permettre le recomptage manuel du stock de soin dans le salon.
196. Interdire un recomptage qui ferait passer le stock physique sous les unités réservées.
197. Consigner les ajustements de stock salon comme mouvements non destructifs avec motif et acteur.
198. Ajouter des tests d'invalidité de catalogue, doublons, limites de taux et isolation inter-salons.
199. Ajouter des tests de prix et commissions historiques ainsi que d'inventaire du salon.
200. Tester le cycle suspension → refus de réservation / vente directe → encaissement d'ancien RDV → réactivation.
201. Éviter le calcul d'un stock négatif ou incohérent lors de l'ajout boutique au panier.
202. Détecter les débordements d'entiers dans l'export CSV d'un inventaire corrompu.
203. Tester l'export d'un inventaire contenant des quantités impossibles sans plantage.
204. Ajouter le franc congolais CDF, le franc rwandais RWF et le franc burundais BIF aux devises initiales.
205. Expliciter la devise de chaque commerce plutôt que de supposer que toute l'Afrique utilise le FCFA.
206. Permettre le choix de la devise dès la création de l'établissement.
207. Empêcher la création dans une devise non prise en charge par les montants entiers.
208. Afficher les devises disponibles dans les réglages propriétaires iOS.
209. Exiger le contrôle du code maître avant une modification de devise existante.
210. Interdire une modification de devise après l'enregistrement de produits, ventes, dépenses ou arrivages.
211. Remplacer les libellés FCFA fixes des prix, remises et reçus boutique par la devise du commerce.
212. Calculer et afficher la monnaie à rendre dans la même devise que l'encaissement boutique.
213. Corriger la devise des coûts de balles, des valorisations et de la saisie de prix.
214. Utiliser la devise de l'établissement pour les prix, additions et montants reçus du restaurant.
215. Utiliser la même devise pour les tickets envoyés en cuisine et les modifications de la carte.
216. Corriger la devise des rendez-vous, encaissements et articles du salon.
217. Corriger la devise du rapport de commissions et des fiches clients salon.
218. Afficher la devise exacte lors de la saisie des dépenses communes aux trois métiers.
219. Ajouter un XCTest de reçu CDF pour vérifier l'absence de conversion ou d'étiquette FCFA erronée.
220. Tester le verrouillage du changement de devise après création d'une dépense ou d'un article, avec isolation inter-commerces.
221. Inclure les arrivages de balles dans le schéma isolé des tests de protection des devises.
222. Vérifier qu'un premier arrivage bloque les changements de devise comme toute autre opération financière.
223. Limiter les collaborateurs affichés dans le rapport salon à la période effectivement sélectionnée.
224. Afficher un état vide explicite lorsqu'un salon n'a ni rendez-vous ni vente dans la période.
225. Préciser que le chiffre après commissions ne déduit pas encore les charges de l'établissement.
226. Définir un format privé CloudKit versionné pour chaque donnée opérationnelle, sans dépendance web.
227. Modéliser les états synchronisables du catalogue, des arrivages et des mouvements de stock immuables.
228. Modéliser les fiches clients, collaborateurs, disponibilités et réservations salon.
229. Modéliser les tables, commandes ouvertes et lignes de préparation du restaurant.
230. Modéliser les historiques de commissions salon et les droits d'accès des responsables.
231. Maintenir les paiements et remboursements dans leurs journaux vérifiés existants plutôt que les déduire d'un état distant.
232. Ajouter un contrôle compare-and-swap CloudKit refusant d'écraser une mise à jour concurrente.
233. Enregistrer localement la dernière version iCloud connue de chaque entité.
234. Refuser une mise à jour distante qui écraserait un changement hors ligne non envoyé.
235. Appliquer les articles et dépendances avant les mouvements, ventes et réservations.
236. Appliquer les entrées de stock une seule fois, sans recopier le compteur physique comme une vérité distante.
237. Vérifier que chaque compteur de stock correspond à la somme de son historique d'entrées et de sorties.
238. Empêcher qu'une quantité incohérente ou concurrente devienne négative après synchronisation.
239. Détecter les rendez-vous en concurrence sur le même créneau, client ou collaborateur.
240. Permettre à un reçu confirmé de terminer une commande restaurant ouverte reçue d'un autre appareil.
241. Refuser le passage de payé à non payé lorsqu'une ancienne commande ouverte arrive en différé.
242. Séparer les synchronisations propres à chaque établissement et à chaque identité iCloud.
243. Intégrer les nouveaux états opérationnels dans la persistance locale SwiftData.
244. Lancer les cycles métiers dans le statut de synchronisation propriétaire sans polling serré.
245. Ajouter des tests de réimportation, inventaires, conflits concurrents et cycle restaurant multi-appareils.
246. Empêcher toute modification rétroactive des mouvements de stock, des balles et des commissions importés.
247. Tester la réplication des annulations de rendez-vous en conservant l'identifiant et l'historique.
248. Tester le refus de deux rendez-vous concurrents pour un même collaborateur.
249. Tester le refus d'une sortie de stock qui ferait passer l'inventaire total sous zéro.
250. Réduire les lectures SwiftData de lignes de cuisine aux seules commandes ouvertes de l'établissement.
251. Conserver exactement les UUID des articles importés afin que stocks, rendez-vous et lignes restent liés.
252. Empêcher qu'un ancien état de table rouvre une addition déjà réglée par un reçu vérifié.
253. Tester l'arrivée du reçu avant un ancien état de salle dans le simulateur.
254. Documenter la réplication CloudKit explicite, les comptes Apple et l'absence de partage du personnel entre identifiants.
255. Auditer les types CloudKit réellement présents dans le conteneur Apple `iCloud.com.covi.app`.
256. Créer les trois types `COVIAccountIndex`, `COVIEvent` et `COVIOperationalState` dans le schéma de développement Apple.
257. Ajouter à chacun un champ `payload` de type `Bytes`, sans toucher aux données métier ni aux profils Apple.
258. Vérifier que le schéma de production est vide et inspecter la prévisualisation de déploiement, sans déployer.
259. Centraliser les noms des record types et du champ `payload` pour éviter des divergences entre le code et CloudKit.
260. Tester deux stocks locaux indépendants avec ventes concurrentes valides et refus de survente du dernier article.
261. Tester les rendez-vous salon concurrents sur deux copies distinctes d'un établissement.
262. Documenter les tests physiques restants et la limite d'ACL de `CKShare` avant toute invitation d'employés.
263. Remplacer la cible hybride de l'ancien workflow TestFlight manuel par le projet SwiftUI/XcodeGen natif, avec préflight XCTest, contrôle du profil CloudKit Production et de Sign in with Apple, version supérieure à 1.0.7 et envoi soumis au drapeau explicite `uploadToTestFlight`. Aucun certificat ni profil Apple n'est créé ou modifié.
264. Exécuter un véritable préflight manuel macOS sans envoi (`uploadToTestFlight=false`, action `44516821945`, commit `8182716`) ; valider l'équipe, le Bundle ID et Sign in with Apple, puis constater le blocage de sécurité : le profil App Store existant ne contient ni conteneur ni service CloudKit ni environnement Production. Arrêt avant compilation/signature/envoi, comme prévu.

## Vérification macOS sans signature (branche de diagnostic uniquement)

Le workflow GitHub Actions `COVI Native iOS Diagnostics` s'exécute sur la branche
`wip/covi-native-20261119-no-testflight`, distincte de la branche Xcode Cloud.
Le second lancement a **compilé l'app et ses tests avec succès** (`build-for-testing`, étape 6).
Il a ensuite exécuté 46 XCTest : 18 réussis, 28 en échec, **dont les erreurs sont toutes liées à
l'accès Keychain non signé** (`OSStatus -34018`, ou refus de caisse qui en découle).
La signature étant volontairement interdite, le stockage sécurisé a été rendu injectable,
avec Keychain inchangé en production et un stockage isolé en mémoire dans les XCTest.
Le troisième lancement de référence (`765f157`, action `44473901012`) a ensuite
**réussi la compilation et les 53 XCTest** sans aucune erreur.
Un quatrième lancement (`b0944ac`) a permis de trouver, au compilateur, deux
affectations ambiguës dans le nouvel éditeur restaurant ; elles ont été corrigées
avant le lancement du lot incluant également dépenses et trésorerie.
Le cinquième lancement (`eebf54c`, action `44475555009`) a **compilé et exécuté
68 XCTest sans aucun échec**. Le lancement ultérieur (`32a49d`, action `44489621987`,
job `135441631979`) a **compilé et exécuté 78 XCTest sans aucun échec**, y compris
le journal CloudKit des dépenses. Les changements de rendez-vous, la suspension boutique
et leurs tests, ainsi que les exports CSV, ont ensuite fait l'objet de
lancements supplémentaires du même workflow de diagnostic.
Depuis, les deux lancements suivants ont également réussi : `3ffe8d4` avec **84/84**
XCTest et `1a6c74e` avec **88/88** XCTest. Le lancement `2b02e7d` a réussi
**92/92 XCTest**, validant le catalogue salon, ses commissions et les blocages
de vente. Le lot de devises d'Afrique centrale et les corrections ajoutées
ensuite ont également été validés : le lancement `68c7de5`, action `44492890062`,
a **compilé l'intégralité du projet et exécuté 97/97 XCTest sans échec** sur
simulateur iPhone macOS, sans signature, sans archive et sans TestFlight.
Ce contrôle ne crée **ni archive de distribution ni provisioning**, et ne valide pas les maquettes.
Le premier lot de miroirs opérationnels (`7b30a00`, action `44500183345`)
**compile sans erreur**, mais son exécution de **108 XCTest présentait 7 échecs**,
liés aux références des articles restaurés avec un identifiant aléatoire.
Le correctif conserve désormais l'identifiant source ; son nouveau contrôle
macOS et le test de table réglée ont ensuite réussi : révision distante
**`2d7e912`**, action **`44501925643`**, job **`135483623881`** :
**build-for-testing réussi et 109/109 XCTest réussis, 0 échec**.
Cette validation couvre la fusion SwiftData en mémoire ; elle ne prouve pas
la disponibilité du CloudKit privé de production ou le partage entre comptes Apple.

L'audit suivant a ouvert **le véritable conteneur Apple** `iCloud.com.covi.app` :
les trois types COVI et leurs champs `payload: Bytes` ont été créés dans le
schéma **Development**. Le schéma **Production** ne comportait aucun type.
La prévisualisation du déploiement annonce trois nouveaux types et des
modifications aux rôles système ; le déploiement a été annulé avant toute
action sur la production. Le protocole détaillé de validation physique et de
partage inter-comptes est dans `native-ios/CLOUDKIT_VALIDATION.md`.
Le lancement de diagnostic suivant, **`4f037fe`**, action GitHub
**`44511213881`** (job `135515635113`), a **compilé sans erreur** et
**exécuté 113/113 XCTest, 0 échec**. Les nouveaux tests valident les deux
bases SwiftData de téléphones simulés, y compris les ventes concurrentes et
l'agenda hors-ligne ; les deux vrais iPhone demeurent nécessaires.

Après l'autorisation de préparer un TestFlight interne, le workflow manuel
`.github/workflows/ios-testflight.yml` a été redirigé vers le projet **natif**
`native-ios/COVI.xcodeproj` (schéma `COVI`). Le mode sans envoi vérifie les
secrets existants, les entitlements du profil de distribution, le projet
généré et les XCTest. Le mode signé est conditionné à une sélection explicite
et contrôle le Bundle ID `com.covi.app`, la version, la signature et l'accès
au CloudKit Production avant transmission. La syntaxe YAML et des 11 scripts
Bash a été vérifiée localement ; **le workflow n'a pas encore été exécuté sur
macOS**, le profil de signature n'est pas encore certifié compatible, et
aucune archive n'a été transmise à Apple.

Le préflight GitHub Actions **`44516821945`** (job `135534878731`) a ensuite
confirmé que la branche et tous les secrets configurés étaient disponibles.
Le profil existant porte le bon Team ID, le Bundle ID `com.covi.app` et
`Sign in with Apple`, mais **aucun des trois droits CloudKit requis**
(identifiant de conteneur, service et environnement `Production`). Le workflow
s'est interrompu avant la compilation et avant tout envoi, conformément aux
protections. Le profil ne sera pas recréé ni modifié par cet agent.

L'inspection du diff **avant** déploiement CloudKit Production a montré que
les trois nouveaux record types recevraient en base **publique** les droits
`GRANT READ TO "_world"`, `GRANT CREATE TO "_icloud"` et
`GRANT WRITE TO "_creator"`. Les zones privées actuellement utilisées par
COVI ne dépendent pas de ces droits publics, mais une publication telle quelle
permettrait de lire les éventuels enregistrements publics de ces types sans
authentification. **Déploiement suspendu** en attendant la confirmation précise
du retrait des droits publics de ces trois types ; le type `Users` préexistant
doit rester inchangé.

## Limites bloquantes

- Une connexion Apple et un compte iCloud ne prouvent **pas** à eux seuls la synchronisation complète :
  les nouveaux miroirs CloudKit exigent encore des essais réels sur deux appareils. Le stockage privé
  du propriétaire ne partage pas automatiquement les données avec le compte Apple d'un employé.
- Les anciens utilisateurs Supabase/Capacitor nécessitent un protocole de migration explicite.
- Les sources des 46 maquettes approuvées ne figurent pas dans ce checkout.
- Aucune archive iOS, aucun fichier de signature ni aucun profil de provisioning n'a été créé ou modifié.
- Aucun push n'a été effectué vers la branche reliée à Xcode Cloud.
