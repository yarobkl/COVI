# COVI — Scénarios de validation avant activation du stock central

Statut : **plan de tests, pas résultats de tests**. Ne pas exécuter contre la base de production.

## Préparation

- Créer deux boutiques A/B avec comptes distincts, catégories identiques, un ballon de 12 robes pour A et un de 4 robes pour B.
- Utiliser une base jetable et des comptes fictifs. Ne jamais utiliser de vrais numéros de téléphone ou photos clients.
- Vérifier les migrations sur une base vierge puis sur une copie anonymisée des anciennes tables ; comparer les totaux avant/après.

## Invariants de stock

1. Réception de 12 robes : A=12, B=4 ; un seul mouvement d'entrée pour A.
2. Rejouer le même identifiant d'opération : aucun ajout supplémentaire ; détecter les paramètres contradictoires.
3. Vendre 5 robes : A=7, un seul débit de 5 et une seule vente.
4. Deux paiements simultanés demandent chacun 5 robes quand 7 restent : au plus un peut réussir.
5. Vendre 0, -1, 1.5 ou une quantité supérieure au disponible : rejet, aucune mutation.
6. Réserver 6 sur 7 : disponible=1 ; une seconde réservation de 2 échoue ; l'expiration rend 6 disponibles sans augmenter le total physique.
7. Un client soumet une demande QR : stock inchangé avant validation du paiement.
8. Double clic / retry réseau sur paiement confirmé : même reçu et une seule décrémentation.
9. Annulation avant paiement : aucun débit ; annulation après paiement nécessite un retour tracé et non une suppression de vente.
10. Aucune écriture cross-shop par substitution de `shop_id`, `arrival_id`, `sale_id` ou `category_id`.

## Sécurité

- Appel anonyme aux RPC privées : refus.
- Compte A tentant de lire/écrire stock B : refus.
- Tentative directe de modifier les nouvelles tables depuis le client : refus.
- Demande QR publique : aucune exposition du stock privé, des téléphones ou des commandes d'autrui.
- Images : contrôle du type, de la taille et de l'autorisation de lecture.
- Vérifier le comportement des anciennes ventes hors connexion et l'idempotence de `record_sale` ; ne pas modifier l'authentification.

## Critères de passage

- Tests unitaires TypeScript, tests SQL en base jetable, tests de concurrence et tests E2E passent.
- Le bilan ne présente pas une marge exacte sans méthode de valorisation du stock restant.
- Les données de test existantes ne sont pas transférées dans le stock réel.
- Aucun merge sur `main`, aucune migration Supabase et aucun déploiement sans validation.
