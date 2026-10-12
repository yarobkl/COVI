# COVI — Caisse V1 sans API de paiement

## Principe non négociable
COVI ne collecte ni ne vérifie automatiquement les paiements Mobile Money.
Le vendeur ou caissier reçoit la preuve du paiement hors COVI (notification
de l'opérateur, SMS, application du fournisseur, espèces remises), la contrôle,
puis appuie sur **Confirmer le paiement reçu**.

## Parcours
1. QR code public, lien de vente social ou saisie manuelle → même file de commandes.
2. Le commerçant contrôle catégories, quantités, prix négociés et disponibilité.
3. Éventuelle réservation temporaire, sans diminution définitive du stock.
4. Le client règle hors application (espèces / Mobile Money / autre).
5. Avant de confirmer, le caissier ou vendeur choisit le moyen de paiement,
   **saisit obligatoirement son prénom**, et peut ajouter une référence
   Mobile Money ou un justificatif (facultatif).
6. Un utilisateur autorisé clique sur **Confirmer le paiement reçu** après
   avoir vérifié la réception effective des fonds.
7. Une transaction atomique serveur crée la confirmation et le reçu, passe la
   commande à `paid`, et déduit les quantités une seule fois.
8. Répéter la même opération ne doit jamais créer un deuxième reçu ni décrémenter
   le stock une seconde fois.

## Règles de confiance
- Afficher **Paiement confirmé par le vendeur** ; ne jamais afficher
  « Paiement vérifié par l'opérateur ».
- **Le prénom saisi n'authentifie personne** : il est déclaré par l'utilisateur
  et conservé tel que validé dans une copie immuable sur le reçu :
  **« Encaissé par : Marie Lou »**.
- Le compte utilisateur lié à l'encaissement est identifié indépendamment.
- `confirmed_by` doit provenir de la session serveur `auth.uid()` ;
  `confirmed_at` de l'horloge serveur.
- La référence SMS/opérateur est facultative et n'est pas une preuve cryptographique.
- Le client ne peut jamais confirmer son propre paiement, même s'il transmet
  une capture d'écran ou une référence.
- Le vendeur ne peut confirmer que les commandes de sa boutique.
- Une commande annulée/expirée/payée est terminale pour la confirmation.
- Les prix sont ceux validés par le vendeur, non ceux arbitrairement modifiés
  depuis une page publique.
- Le statut payé et le reçu ne sont pas modifiables directement depuis le navigateur.
- Les commandes de démonstration ne doivent jamais affecter le stock réel.

## État d'implémentation
- Types et transitions côté TypeScript : écrits, tests ajoutés, exécution non confirmée.
- Schéma SQL : brouillon sur branche, non appliqué.
- Autorisation réelle des vendeurs/employés : à définir et vérifier.
- RPC atomique de confirmation : à développer et tester en base isolée.
- Formulaire de confirmation avec prénom obligatoire et reçu « Le Cahier » :
  composants ajoutés sur la branche de travail, **pas encore connectés à la caisse**.
- Tests associés : écrits, pas encore confirmés exécutés.
- API Mobile Money : aucune requise ni intégrée.
- Production et authentification Google/Facebook : inchangées.
