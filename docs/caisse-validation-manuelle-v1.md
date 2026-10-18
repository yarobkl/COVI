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
- Schémas SQL : brouillons sur branche, non appliqués. La création et l'approbation manuelles sont désormais écrites dans draft_create_approve_manual_checkout_order.sql.
- Autorisation réelle des vendeurs/employés : à définir et vérifier.
- RPC atomique de confirmation : **brouillon implémenté sur la branche** (`supabase/sql-drafts/draft_confirm_manual_checkout_payment.sql`), **non appliqué** et à tester en base isolée. La version actuelle autorise uniquement le propriétaire authentifié ; les comptes employés nécessitent un modèle de permissions distinct.
- Formulaire de confirmation avec prénom obligatoire et reçu « Le Cahier » :
  composants ajoutés sur la branche de travail. `CashierCheckoutPanel` relie le formulaire à la future RPC, mais **n'est pas monté sur les routes de l'application**.
- Tests associés : tests unitaires du formulaire, du reçu, du client RPC et de la réutilisation de l'identifiant lors d'une reprise réseau ajoutés ; **exécution non confirmée**.
- API Mobile Money : aucune requise ni intégrée.
- Production et authentification Google/Facebook : inchangées.

## Conditions de mise en service (bloquantes)

1. Exécuter les migrations de brouillon sur une base Supabase isolée. Une branche payante éventuelle requiert une validation du coût, et aucune n'a été créée.
2. Confirmer le comportement de la RPC à la concurrence : deux validations sur la même commande et deux ventes de la dernière pièce.
3. Tester les autorisations : client anonyme et propriétaire d'une autre boutique refusés, propriétaire légitime autorisé. Un prénom seul n'ouvre jamais un droit.
4. Vérifier que toute erreur annule ensemble le mouvement de stock, la vente, le reçu et le compteur de factures.
5. **Tester** les deux RPC de création puis approbation de commande dans une base isolée. Leur implémentation est écrite sur la branche, non exécutée. Elles autorisent uniquement le propriétaire, et la confirmation refuse encore `reserved` tant que les réservations ne sont pas implémentées.
6. Adapter le tableau de bord pour afficher les lignes par catégorie des ventes récentes ; l'ancien tableau de bord lit encore `sale_items` propre aux produits individuels.
7. Revoir les droits du propriétaire SQL `SECURITY DEFINER`, les fonctions exposées et les permissions des futurs employés.
8. Valider `npm run typecheck`, `npm test`, `npm run lint` puis effectuer des tests réels sur mobile avant toute mise en production.
9. Exécuter la matrice des tests concurrents et des permissions : voir docs/manual-checkout-isolated-validation.md.

**Sécurité des migrations :** les cinq brouillons SQL résident dans `supabase/sql-drafts/`, hors du dossier exécutable `supabase/migrations/`. Un contrôle statique bloquant a été ajouté au workflow CI de la branche.
