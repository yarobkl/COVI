# COVI Scan et Studio — premier lot natif

26 novembre 2026. La caméra et la photothèque système alimentent Vision et Core Image localement, avec propositions prudentes de type et couleur, fond beige, légère correction lumineuse, original/Studio et partage natif. Le commerçant valide le nom, la description, le prix et la quantité avant sauvegarde. Les photos sont stockées dans le répertoire privé protégé par établissement/article ; aucun changement de schéma SwiftData ni appel IA externe. Le stock initial est journalisé avec le produit et une permission propriétaire/responsable relue.

Limites de ce lot : analyse d'une image à la fois ; classification générique Vision et seuils conservateurs à calibrer sur de vrais vêtements. Pas encore d'index de similarité en caisse, d'arrivage continu, de synchronisation des médias, de suppression automatique à J+30 ni de migration de photos. Les photos locales sont exclues des sauvegardes de l'appareil à ce stade, elles ne doivent pas être présentées comme synchronisées. La sauvegarde du média précède la transaction SwiftData et est retirée sur erreur ; une interruption brutale entre les deux exige un futur nettoyage des orphelins. Tests ajoutés, compilation iOS et rendu simulateur à confirmer dans les diagnostics. Aucun envoi TestFlight ni mutation production.

## Recherche photo en caisse

Le bouton caméra dans Vendre accepte la caméra ou la photothèque et classe localement jusqu’à huit articles disposant d’une photo, à partir des empreintes Vision. Le vendeur confirme l’article avant son ajout au panier. La disponibilité est vérifiée au choix et à l’encaissement. La recherche calcule les empreintes à chaque scan ; les performances sur un catalogue de plusieurs centaines de photos restent à mesurer.

Studio centre le sujet détouré sur le fond beige, avec une marge et sans agrandissement ni déformation. L’original et l’aperçu de la prise de vue utilisent toujours leur cadrage initial.
