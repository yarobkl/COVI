# COVI — Recette Salon professionnel (GPT-04)
Source : PR #64, `docs/salon/AUDIT-ET-ARCHITECTURE.md` et migrations `20261024090000` à `20261024095000`. Statut : spécification, pas une validation exécutée.
Responsables techniques : CLA-05 (UI/métier) ; CLA-02 (migrations/permissions). Base de test : `stcsjwxmmxnjwisqkudz`.

| ID | Priorité | Scénario | Résultat attendu |
| --- | --- | --- | --- |
| SAL-001 | P0 | Deux RDV 10:00–10:30 pour le même coiffeur | Le second est refusé y compris si demandes concurrentes ; contrainte DB effective |
| SAL-002 | P0 | Deux coiffeurs distincts ont chacun un RDV 10:00–10:30 | Les deux RDV sont admis si habilitations/horaires valides |
| SAL-003 | P0 | Rendez-vous pendant absence ou hors horaires individuels | Refus sans réservation partielle |
| SAL-004 | P0 | Coiffeur non habilité pour une prestation | Refus serveur, même si l'UI a été contournée |
| SAL-005 | P0 | Propriétaire donne accès coiffeur via code d'invitation fictif | Code à usage unique ; second usage refusé ; rôle restreint |
| SAL-006 | P0 | Coiffeur tente lecture du fichier clients complet ou rembourse une note | Accès refusé ; pas de donnée personnelle divulguée |
| SAL-007 | P0 | Ticket avec prestation 12 000 + produit 6 000 ; paiement 10 000 espèces + 8 000 Mobile Money | Total et encaissement = 18 000 XAF une seule fois, confirmation Mobile Money indiquée comme **manuelle** |
| SAL-008 | P0 | Rejouer la même clé d'opération de SAL-007 | Pas de double paiement, stock ou commission |
| SAL-009 | P0 | Rembourser une ligne payée ; rejouer le remboursement | Une écriture de remboursement seulement ; motif obligatoire ; stock restitué uniquement si action explicitement demandée et autorisée |
| SAL-010 | P0 | Boutique/salon B interroge ou modifie Salon A | Refus multi-tenant même avec UUID connu |
| SAL-011 | P1 | Consommable nécessaire 30 ml, stock disponible 20 ml | La prestation suit la règle prévue : ne pas bloquer la caisse ; sortie 20 ml, manque 10 ml signalé, sans stock négatif |
| SAL-012 | P0 | Vente fin septembre puis remboursement en octobre | Vérifier la date de l'ajustement CA et du décaissement ; **arbitrage propriétaire requis**, voir FIN-004 |
| SAL-013 | P1 | Affichage Salon avec PR #66 + PR #64 | Navigation, écrans, paiements, agenda et tableau de bord cohérents à 390 et 1280 px, aucune touche <44px |
| SAL-014 | P0 | Migration Salon absente/partielle et appel fonction sensible | Échec explicite sans privilèges étendus, ni écriture partielle |

## Non-périmètre reconnu
Réservation publique par QR/lien, paiement partiel à crédit et confirmation automatique d'opérateur ne sont pas des exigences de cette V1 tant qu'une décision de produit ne les ouvre pas.

## Preuves
CLA-05 et CLA-02 renseignent, pour chaque cas, la fonction appelée, les préconditions, le résultat serveur, les événements en base et les traces de permissions. Ne jamais utiliser la base de production.
