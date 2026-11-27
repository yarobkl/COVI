# COVI Scan et Studio — premier lot natif

26 novembre 2026. La caméra et la photothèque système alimentent Vision et Core Image localement, avec propositions prudentes de type et couleur, fond beige, légère correction lumineuse, original/Studio et partage natif. Le commerçant valide le nom, la description, le prix et la quantité avant sauvegarde. Les photos sont stockées dans le répertoire privé protégé par établissement/article ; aucun changement de schéma SwiftData ni appel IA externe. Le stock initial est journalisé avec le produit et une permission propriétaire/responsable relue.

Limites de ce lot : analyse d'une image à la fois ; classification générique Vision et seuils conservateurs à calibrer sur de vrais vêtements. Pas encore d'index de similarité en caisse, d'arrivage continu, de synchronisation des médias, de suppression automatique à J+30 ni de migration de photos. Les photos locales sont exclues des sauvegardes de l'appareil à ce stade, elles ne doivent pas être présentées comme synchronisées. La sauvegarde du média précède la transaction SwiftData et est retirée sur erreur ; une interruption brutale entre les deux exige un futur nettoyage des orphelins. Tests ajoutés, compilation iOS et rendu simulateur à confirmer dans les diagnostics. Aucun envoi TestFlight ni mutation production.

## Recherche photo en caisse

Le bouton caméra dans Vendre accepte la caméra ou la photothèque et classe localement jusqu’à huit articles disposant d’une photo, à partir des empreintes Vision. Le vendeur confirme l’article avant son ajout au panier. La disponibilité est vérifiée au choix et à l’encaissement. La recherche calcule les empreintes à chaque scan ; les performances sur un catalogue de plusieurs centaines de photos restent à mesurer.

Studio centre le sujet détouré sur le fond beige, avec une marge et sans agrandissement ni déformation. L’original et l’aperçu de la prise de vue utilisent toujours leur cadrage initial.

## Arrivages photo

Depuis Boutique → Stock → Arrivages, un propriétaire ou un responsable sélectionne l’origine et peut enchaîner les captures ou sélectionner jusqu’à 450 photos en photothèque. Chaque fichier est enregistré localement avant que la capture suivante soit autorisée, sans lancer Vision. La liste des captures en attente se rouvre par établissement et origine. L’analyse et le Studio s’exécutent à l’ouverture de la fiche. La confirmation réutilise la création d’article existante et l’identifiant de la capture évite un second mouvement de stock en cas de reprise après sauvegarde.

L’origine organise les files de captures. Le rattachement de chaque article à un lot commercial distinct, la préparation de plusieurs fiches en arrière-plan et les coûts et variantes restent à intégrer. La prise de vue en série et son orientation restent à vérifier sur appareil.

## Préparation des captures par lots

L’action « Préparer les photos avec COVI Studio » traite les captures en attente une par une et conserve chaque résultat dans un cache local protégé. Le cache contient les propositions, l’aperçu et le résultat Studio. L’original reste dans son fichier de capture. La fiche article réutilise le résultat disponible, puis le commerçant confirme le nom, le prix et la quantité.

La préparation est suspendue quand l’application devient inactive ou que l’utilisateur quitte la file. La reprise réutilise les résultats terminés. Les captures et leurs analyses sont retirées ensemble après la création de l’article ou une suppression explicite. Le maintien du traitement pendant une suspension prolongée d’iOS reste à développer. Les essais caméra sur appareil, les coûts et variantes, la synchronisation et la conservation J+30 restent ouverts.

Validation du lot : le diagnostic macOS 45881995888 a réussi sur le commit fe336fe, avec 144 XCTest sans échec, compilations Debug et Release pour simulateur et captures de régression iPhone/iPad. Le test du cache vérifie sa réutilisation sans réécriture, la conservation de l’original et sa suppression avec la capture. La vitesse sur un gros lot de photos réelles et les interactions du nouvel écran sur appareil restent à vérifier.

## Rattachement du stock initial à un lot d’achat

Le formulaire de création d’article propose un lot existant de la boutique. Lorsque le stock initial est positif, son mouvement conserve le lien vers ce lot. Le service refuse un lot d’un autre établissement avant toute création. Le choix reste facultatif. La répartition du coût global du lot entre les articles, les coûts unitaires et les variantes restent à développer.

Le diagnostic macOS 45883944148 a réussi sur ae59479, avec 146 XCTest sans échec, compilations Debug et Release pour simulateur et captures de régression iPhone/iPad. Le test dédié vérifie le rattachement au bon lot et le refus d’un lot étranger sans création d’article. Les interactions de ce formulaire sur appareil restent à vérifier.

## Coût facultatif des lots

Le coût du lot peut rester vide. La fiche affiche alors « Non renseigné ». Un zéro saisi reste un coût explicitement connu. Les montants historiques sont considérés comme connus via un indicateur persistant dont la valeur par défaut est vraie. Les calculs doivent utiliser knownCost pour tenir compte de l’absence de coût.

Le format de synchronisation conserve les coûts entiers existants et accepte un coût absent pour les nouveaux lots. Les anciennes versions qui exigent ce champ ne peuvent pas importer les lots sans coût et nécessitent une mise à jour. Les essais de migration d’une ancienne base sur appareil et de synchronisation entre deux appareils restent nécessaires avant livraison. La répartition du coût global et les marges unitaires restent à développer.

Validation du 27 novembre 2026 : le diagnostic macOS 45937968779 a réussi sur 2412a66, avec 153 XCTest sans échec, compilations Debug et Release pour simulateur et captures de régression iPhone/iPad. Les tests vérifient la distinction coût absent/zéro/montant connu, la lecture des montants numériques et la conservation des valeurs après synchronisation répétée et relecture dans un nouveau contexte. La migration d’une ancienne base sur appareil reste à vérifier avant livraison.

## Vérification de la migration des coûts — 27 novembre 2026

Le test LotCostMigrationTests crée un fichier SQLite persistant avec le modèle Bale antérieur à costKnown, deux coûts historiques (zéro et 12 500), un article et son mouvement de stock lié au lot. Le fichier est ensuite ouvert par PersistenceController.makeContainer, le point d’entrée réel de l’application. Le test vérifie les coûts et leur statut connu, les UUID, la date du lot, la quantité de stock et le rattachement du mouvement. Un nouveau lot sans coût est ajouté, puis une nouvelle ouverture vérifie sa conservation sans confusion avec le zéro historique.

Diagnostic macOS 45940015752 réussi sur d14981d, avec 154 XCTest sans échec, compilations Debug et Release pour simulateur et captures de régression iPhone/iPad. Cette vérification couvre la migration du modèle des coûts sur une base de test reproduisant l’ancien format. L’essai de l’installation physique existante et la compatibilité multi-appareils restent à effectuer avant livraison.
