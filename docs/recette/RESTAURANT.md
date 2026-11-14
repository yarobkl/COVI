# COVI — Recette Restaurant (GPT-03)
Statut : scénarios à exécuter par CLA-04 en préproduction isolée ; aucun test réel exécuté par GPT.
Périmètre : plan de salle, table, carte, service/cuisine, encaissement, QR public. Ne présumer ni une passerelle paiement opérateur ni des commandes QR de groupe activées.

| ID | Priorité | Scénario fictif | Critère d'acceptation |
| --- | --- | --- | --- |
| RES-001 | P0 | Créer 6 tables puis ouvrir la table T1 | 6 tables distinctes, T1 identifiée sans chevauchement visuel à 390/1280 px |
| RES-002 | P0 | T1 : deux plats à 4 500 XAF + boisson 1 500 XAF | Total attendu 10 500 XAF ; quantités et prix corrects, état de commande traçable |
| RES-003 | P0 | Deux collaborateurs modifient T1 simultanément | Pas de commande perdue, doublée ni d'encaissement double ; comportement d'erreur ou verrouillage explicite |
| RES-004 | P0 | T1 en préparation puis servie puis réglée | Transition valide ; états cuisine, salle, caisse cohérents et auditables |
| RES-005 | P0 | Scanner le QR de T1 en anonyme | Carte du **bon restaurant et de la bonne table** en lecture seule ; aucune donnée de client ou d'administration exposée |
| RES-006 | P0 | QR invalide / modifié / d'un autre établissement | Réponse fermée ; aucune exposition inter-établissements |
| RES-007 | P0 | Sur la carte QR publique, tenter une opération non activée (commande de groupe) | Fonction refusée si interrupteur de sécurité ou protection anti-abus non validés |
| RES-008 | P1 | Annuler une ligne avant encaissement | Total recalculé ; événement enregistré ; aucune quantité facturée à tort |
| RES-009 | P1 | Annuler/rembourser après encaissement, selon capacités réelles | Trace non destructive, pas de double remboursement ; distinguer débit de caisse et ajustement de ventes |
| RES-010 | P1 | Imprimer un QR et le scanner depuis un autre téléphone | Code noir/blanc lisible, marge préservée, impression sans contrôles de l'application |
| RES-011 | P0 | Utilisateur d'un restaurant B appelle les fonctions de T1 du restaurant A | Accès refusé, état et totaux inchangés |
| RES-012 | P1 | Couper et rétablir le réseau pendant le service | Pas de confirmation erronée ; état serveur rechargé correctement |

## Points à documenter avant la recette
- Lister les capacités **effectivement activées** sur `integration/preprod` ; identifier « non implémenté », « volontairement désactivé » et « défaut ».
- Préciser si les remises, paiements mixtes et remboursements sont pris en charge en restaurant ; ne pas inventer de résultat.
- Preuves de CLA-04 : requêtes masquées, états avant/après et captures 390/1280 px, aucun secret ni donnée client réelle.
