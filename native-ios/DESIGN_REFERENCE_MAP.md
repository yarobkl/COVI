# COVI iOS — références visuelles fournies par Rodrin

Source de vérité : **les nouvelles captures partagées dans la conversation du 19 novembre 2026**. Ne pas importer les anciennes planches COVI de Figma, les explorations précédentes ou les chiffres de démonstration dans les données métier.

## Reprise du lot visuel COVI 2.0

- Le build TestFlight 1.0.13 (10051), issu du commit `6eb37ed`, valide la
  chaîne de livraison. Le lot de refonte visuelle reste en cours.
- La planche `5AD6CB67-3D94-4E19-90A7-FDF8F948CAC6.jpeg` contient le lancement
  et l’accueil. Le titre, le texte et les deux actions correspondent au
  texte SwiftUI actuel. La comparaison du rendu sur iPhone reste à faire.
- La planche `6906CB2C-1753-474A-A3CF-D5121DE79AE7.jpeg` et ses trois copies
  retrouvées affichent **Connexion et Inscription**. La correspondance
  Boutique de l’inventaire historique est erronée pour ces fichiers.
  Identifier la planche Boutique par son contenu avant l’implémentation.

## Inventaire vérifié

Les pièces jointes accessibles dans ce lot comprennent **16 fichiers JPEG composites, dont 15 différents**. Elles présentent **35 captures d'écran iPhone au total**, avec des variantes de trois vues Restaurant. Le projet mentionne historiquement « 20 lots / 46 écrans » : cette totalité n'est **pas attestée par les fichiers actuellement reçus**.

| Référence jointe (identifiant du fichier) | Vues représentées | SwiftUI de référence | État de reproduction |
| --- | --- | --- | --- |
| `9BF220F7` | Se connecter, Créer un compte | `AppSession.swift` | Habillage avancé ; identifiants e-mail/mot de passe/Google non disponibles dans le service de comptes actuel |
| `17327825` | Votre établissement, Mes espaces | `RootView.swift` | Sélection des activités et espaces branchée aux vraies données ; adresse, pays et téléphone non stockés par le modèle actuel |
| `5AD6CB67` | Écran de lancement, Présentation COVI | `RootView.swift` | Capture réelle iPhone réalisée, puis recadrage de l’image des trois métiers corrigé pour retirer un texte parasite ; seconde capture à contrôler |
| `13FF89C0` | Code PIN collaborateur, Synchronisation | `PINEntryView.swift`, `MoreSpace.swift` | Pavé numérique PIN et centre de synchronisation reliés aux services ; changement de collaborateur non câblé |
| `6906CB2C` | Connexion et inscription dans les fichiers retrouvés | `RootView.swift` | Planche Boutique à identifier séparément |
| `2A49F962` | Restaurant : Tables, Table 01, Commander | `RestaurantSpace.swift`, `RestaurantMenu.swift` | Nouvelle grille, détail et commande reliés aux tables et tickets |
| `A30B3A65` | Variante Restaurant : Tables, Table 01, Commander | mêmes fichiers | Variante présente : **ne pas fusionner silencieusement les deux versions** ; validation du choix final à faire |
| `058F98E6` | Restaurant : Équipe & Accès, Rapports service | `OwnerSettings.swift`, `MoreSpace.swift` | Fonctions de sécurité/rapports existantes ; apparence à finaliser |
| `C0053217` | Restaurant : Gestion de la carte, Stock boissons | `RestaurantMenu.swift` | Gestion de carte existante ; réservations de boissons et écran de réassort spécifiques non réalisés |
| `6155DBBE` | Restaurant : Cuisine, Encaissement partiel, Incident | `RestaurantSpace.swift`, `RestaurantService.swift` | Cuisine opérationnelle ; encaissement partiel et incident/remboursement spécifiques non réalisés |
| `A2188A03` | Salon : Aujourd’hui, Agenda, Nouveau rendez-vous | `SalonSpace.swift` | Résumé du jour, grille horaire par collaborateur et formulaire de réservation reliés au contrôle de chevauchement ; capture comparative encore à effectuer |
| `57D4B495` | Salon : Clients, Fiche client | `SalonSpace.swift` | Liste, historique, modification et rendez-vous depuis la fiche reliés aux données |
| `683EE982` | Salon : Caisse, Catalogue | `SalonCheckout.swift` | Encaissement et catalogue existants ; finition visuelle à compléter |
| `657B79B7` | Salon : Demandes en ligne, Rapports salon | `SalonCheckout.swift` | Rapport relié aux opérations ; demandes publiques Instagram/QR non intégrées |
| `D2C012FF` | Salon : Plus, Paramètres | `MoreSpace.swift`, `SystemSettings.swift` | Plus restructuré ; paramètres et rôles à finaliser |

Le fichier `D2C012FF…(20261119-142926).jpeg` est identique au précédent et n’est **pas un seizième lot distinct**.

## Critères de validation encore obligatoires

1. Capturer chaque vue sur iPhone de même taille et comparer **typographie, textes, couleurs, espacement, images, états, boutons et flux** à la maquette retenue.
2. Vérifier que chaque contrôle visible déclenche une vraie route, lecture, sauvegarde ou mutation autorisée ; ne pas simuler les paiements ni les connexions externes.
3. Tester les rôles, le PIN, les refus, les stocks, les remboursements, la prise de rendez-vous et la synchronisation entre deux vrais iPhone.
4. Ne déclarer aucun des 46 écrans « conforme à 100 % » avant ces contrôles.
5. Ne pas envoyer de version en distribution publique pour valider seulement l'apparence.
