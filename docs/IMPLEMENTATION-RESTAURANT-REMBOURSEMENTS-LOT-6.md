# COVI — Lot 6 Restaurant : remboursement espèces effectivement remis

**Date : 17 octobre 2026**  
**Branche isolée** : `feature/covi-restaurant-salon-v1`, PR brouillon 44.  
**Publication** : aucune migration de production, aucune fusion et aucun déploiement.

## Invariant financier

Une réclamation concernant un plat ou une boisson déjà servi(e) n'est **pas** un remboursement. Le propriétaire peut classer le ticket « remboursement à examiner ». Tant qu'il n'a pas réellement rendu d'espèces et confirmé cette action dans COVI, **aucun décaissement** ne doit apparaître dans la comptabilité.

Quand des espèces sont physiquement remises, COVI écrit un enregistrement supplémentaire **append-only** dans `restaurant_cash_refunds`, sans supprimer ni inverser artificiellement l'encaissement original :

- **Encaissements bruts espèces** = somme de `restaurant_cash_payments.amount_xaf`.
- **Remboursements espèces effectués** = somme de `restaurant_cash_refunds.amount_xaf`.
- **Solde net espèces de ces ventes** = encaissements bruts moins remboursements effectivement remis.
- **Stock et disponibilité des tables** ne sont pas réécrits à l'occasion de ce remboursement.

Il faut afficher ces trois montants séparément dans les futurs bilans, sans les confondre avec le chiffre d'affaires comptable, la marge ou la trésorerie globale.

## Sécurité et exactitude

- RPC `restaurant_cash_refund_quote` réservée au propriétaire, calculant en base les plafonds par addition et par article.
- RPC `restaurant_confirm_cash_refund` réservée au propriétaire, demandant montant positif, motif explicite, identifiant d'opération et confirmation explicite que l'argent a **déjà** été physiquement rendu.
- Une seule sortie pour chaque incident, et réutilisation idempotente de la même référence d'opération si l'écran est interrompu.
- Verrou PostgreSQL de la session avant chaque contrôle et écriture : les sorties parallèles ne peuvent dépasser l'encaissement réel, ni la valeur initiale de l'article.
- Prix original de l'article conservé en base. Aucune modification du stock ni du paiement original.
- Identité de l'auteur et heure du décaissement enregistrées dans le registre et dans le journal privé du restaurateur.
- Chiffres `bigint` XAF traités comme chaînes entières dans les réponses JSON de calcul pour éviter les pertes de précision.
- Aucun accès de lecture aux serveuses, cuisiniers, caissières, invités QR ou établissements tiers.
- L'interface rappelle sans ambiguïté : _un remboursement à examiner_ n'est pas _un remboursement effectué_.

## Scénarios des tests SQL

1. Interdire au serveur ou à un autre restaurant de confirmer une sortie espèces.
2. Refuser le décaissement avant attestation de remise effective.
3. Refuser une somme plus importante que le paiement réellement enregistré.
4. Autoriser deux remboursements sur deux incidents distincts dans la limite des 3 000 FCFA reçus.
5. Refuser de dépasser ce plafond au deuxième remboursement.
6. Refuser un deuxième paiement du même incident, ou une référence rejouée avec un autre montant.
7. En cas de double clic avec les mêmes données, renvoyer la même confirmation sans créer une deuxième sortie.
8. Vérifier que la vente brute, le statut payé de la table, le stock et le journal d'événements restent intègres.

## Ce qui n'est PAS intégré dans ce lot

- Remboursement automatique vers Mobile Money, carte bancaire ou autre prestataire.
- Reversement à distance. La fonction **enregistre** un paiement d'espèces déjà réalisé; elle ne déclenche pas un décaissement.
- Remboursements d'articles non servis / avant règlement, à distinguer du processus d'annulation existant.
- Simulations multi-appareils en conditions réseau réelles, push cuisine hors application, rapport financier consolidé.

**Conditions inchangées** : DA « Le Cahier », isolation stricte des établissements, vérification complète des chiffres avant mise en production et approbation explicite.
