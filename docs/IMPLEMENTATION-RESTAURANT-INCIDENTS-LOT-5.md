# COVI — Restaurant : suivi des incidents après service (lot 5)

**Date : 17 octobre 2026**  
**Branche :** `feature/covi-restaurant-salon-v1` — Pull Request n°44, brouillon.  
**Déploiement :** NON. Aucune migration Supabase réelle, aucun changement Vercel production.

## Ce que fait ce lot

1. La salle des employés conserve désormais les **lignes annulées**. Le personnel voit la
   mention « Annulé (non facturé) » ; les additions et montants restants utilisent seulement
   les statuts `ordered` et `served`.
2. Une personne autorisée (serveuse, cuisine ou caisse) peut **signaler un incident**
   concernant une ligne `served`, sans annuler le plat ni corriger artificiellement les chiffres.
   Chaque rapport indique le plat, la session, le compte de l'employé, la description, l'heure
   et un identifiant de tentative à rejouer sans doublon.
3. Un ticket d'incident ne modifie **jamais** un paiement, le statut de la table, la réservation
   de boissons ni le stock physique. Il peut être ouvert même après une clôture et un
   encaissement réel.
4. Dans son administration, le propriétaire voit une file des incidents à examiner et peut
   les classer « examiné », « rejeté » ou « remboursement à examiner ». Une note de 12 à 500
   caractères est obligatoire.
5. **Remboursement à examiner n'est PAS un remboursement effectué.** La gestion effective
   des retours d'espèces exige un registre de décaissement contrôlé, des plafonds de remboursement,
   une référence de transaction et une confirmation de sortie d'argent. Elle n'est pas livrée
   dans ce lot. Aucun solde de caisse n'est corrigé à l'étape de la simple revue.
6. Les interventions sont consignées dans le journal nominatif, consultable uniquement
   par le propriétaire et isolé par `shop_id`.
7. Les employés ne peuvent ni consulter la file propriétaire ni prendre les décisions.
   Les QR publics ne donnent aucun accès à ces nouvelles fonctions.

## Contrôles

- Un article non servi ne peut pas déclencher un incident « déjà servi ».
- Le même identifiant d'opération renvoie la même déclaration, au lieu de créer un doublon.
- Un identifiant rejoué pour un article ou un motif différent est refusé.
- Un autre restaurant ne peut ni lire ni examiner le ticket.
- Une employée ne peut pas approuver son propre incident.
- Après encaissement de 3 000 FCFA, la revue du ticket ne modifie ni les 3 000 FCFA
  enregistrés ni les deux boissons réellement sorties du stock.
- Les tests s'exécutent sur PostgreSQL jetable et la transaction se termine par `ROLLBACK`.

## Ce qui reste au chantier Restaurant

- Notifications cuisine **push en arrière-plan** (aujourd'hui seulement alerte dans l'application
  ouverte synchronisée), y compris consentement et fonctionnement avec faible réseau.
- Véritable remboursement confirmé avec journal comptable et validation du propriétaire.
- Essais bout en bout avec plusieurs vrais mobiles, comptes de service et caisse, perte réseau,
  double paiement, paiement partiel, annulations et libération des tables.
- Préparation du déploiement seulement après audit des droits et validation explicite.

**La DA « Le Cahier » n'est pas remplacée. Les changements sont incrémentaux.**
