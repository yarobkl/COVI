# COVI — Recette Boutique / Retail (GPT-02)
Statut : spécification indépendante, **non exécutée**. Préproduction fictive exclusivement. Responsable technique : CLA-03.
Références : `src/features/sale/SalePage.tsx` et `src/lib/covi.ts` (branche main consultée le 24/10/2026). Les résultats doivent être corroborés par l'API et la base de test.

## Environnement et préconditions
- Projet Supabase **autorisé uniquement** : `stcsjwxmmxnjwisqkudz` (covi-preprod). **Interdit** : `bmbwmwgfzrijglzcgjut` (production).
- Deux boutiques fictives A et B, chacune avec propriétaire et caissier distincts, aucune donnée réelle.
- Conserver les identifiants d'opération pour tester les doublons, enregistrer l'état initial et l'état final des produits, ventes, ventes par caisse et mouvements.
- Distinguer montant encaissé, chiffre d'affaires, récupération du coût de l'arrivage et résultat : ils ne sont **pas** interchangeables.

| ID | Priorité | Précondition / opération | Résultat attendu |
| --- | --- | --- | --- |
| RET-001 | P0 | Boutique A, pièce unique « Robe test » en stock 1, prix 15 000 XAF ; vendre 1 unité à 15 000 | Une seule vente de 15 000, stock 1→0 ; pièce non revendable ; historique mis à jour |
| RET-002 | P0 | Article non unique stock 3, prix affiché 12 000 ; vendre 2 unités à 11 500 | Montant encaissé 23 000 ; stock 3→1 ; écart au prix affiché 1 000 au total ; aucune ligne en double |
| RET-003 | P0 | Réémettre l'opération de RET-002 avec **le même** `client_operation_id` | Aucune nouvelle vente ; aucun nouveau mouvement de stock ; réponse cohérente de déduplication |
| RET-004 | P0 | Tenter de vendre 2 unités alors qu'il n'en reste qu'une | Refus de dépassement ; stock inchangé ; aucun encaissement enregistré |
| RET-005 | P0 | Deux appareils vendent simultanément le dernier article | Une seule vente aboutit, pas de stock négatif ; l'autre doit recevoir un refus métier explicite |
| RET-006 | P0 | Simuler coupure réseau lors d'un envoi dont l'issue est inconnue, puis reprise | Même identifiant d'opération au renvoi ; aucune vente doublée ; file hors ligne traçable |
| RET-007 | P1 | Arrivage ballon fictif à coût global 60 000 ; ventes cumulées 25 000 + 30 000 + 20 000 | Recettes liées au ballon = 75 000 ; coût d'acquisition récupéré ; **excédent brut sur coût du ballon** = 15 000, à ne pas afficher comme bénéfice net si charges non déduites |
| RET-008 | P0 | Compte de la boutique B essaie de lire/écrire produits, ventes, clients ou caisse A | Aucune donnée de A exposée ; écriture refusée ; contrôle serveur et RLS |
| RET-009 | P1 | Caissier avec remise plafonnée tente une remise au-dessus du plafond | Refus explicite ou contrôle conforme aux règles de permissions ; aucune opération partielle |
| RET-010 | P1 | Journal sur période et filtre « Exemple » | Les ventes TEST ne doivent pas entrer dans les indicateurs réels ; vérifier échantillon et totaux |

## Preuves attendues de CLA-03
- Par scénario : horodatage, identifiant fictif des objets, montants attendus / obtenus, stocks avant/après, résultat PASS/FAIL, trace de test sans secret.
- Pour RET-003/005/006, prouver les invariants **sur le serveur** (pas uniquement dans l'interface).
- Anomalies : ouvrir un commentaire sur la PR correspondante ou les inscrire dans `docs/recette/anomalies.md`. Ne pas modifier les fichiers techniques depuis l'équipe GPT.
