# COVI — Backlog de validation V1 (GPT-01 / GPT-07)
Date : 24 octobre 2026. Aucun chantier technique créé par GPT ; affectation selon la matrice Claude/ChatGPT validée.

## Objectif de livraison
COVI doit permettre à une PME fictive de réaliser les opérations essentielles en Boutique, Restaurant et Salon avec des **montants justes**, une **séparation stricte entre établissements** et une interface Wave cohérente sur smartphone. Les PR #64 (Salon) et #66 (Wave) restent en brouillon tant que la préproduction n'a pas démontré l'ensemble.

| Priorité | Chantier | Porteur technique | Porteur exigences | Condition de sortie |
| --- | --- | --- | --- | --- |
| P0 | Préproduction réellement isolée | CLA-02 | GPT-06 | Référence `stcsjwxmmxnjwisqkudz` prouvée, aucune écriture possible en production |
| P0 | Migrations Salon et RLS | CLA-02 | GPT-04/GPT-06 | Historique ordonné, tests d'isolation et permissions négatives réussis |
| P0 | Vente, stock, caisse Boutique | CLA-03 | GPT-02/GPT-05 | RET-001..006, FIN-001 : tests indépendants conformes |
| P0 | Restaurant tables, commandes, QR | CLA-04 | GPT-03 | RES-001..007, 011 : tests conformes ; activation QR documentée |
| P0 | Agenda et caisse Salon | CLA-05 | GPT-04/GPT-05 | SAL-001..010, 012, FIN-002..006 conformes |
| P0 | Décision remboursement sur mois clos | Propriétaire, puis CLA-05 | GPT-05 | Règle FIN-004 approuvée et testée |
| P0 | Intégration PR #64 + #66 | CLA-01/CLA-06 | GPT-06 | Interface et flux E2E sur branche isolée, CI verte |
| P1 | Application mobile 390/1280 et QR papier | CLA-06/CLA-07 | GPT-07/GPT-06 | Captures, tests touches, scan + impression physique |
| P1 | CI reproductible et rollback | CLA-07 | GPT-06 | Historique versions/commandes, procédure de retour arrière testée |
| P2 | CRM, abonnements, publication des apps | CLA-07 après décision | GPT-07 | Périmètre commercial explicitement validé avant code |

## Décisions à tracer
- Règle de correction CA pour remboursement post-clôture (FIN-004).
- Effets réels du check Cloudflare en échec et nécessité ou non de le corriger.
- Activation des commandes publiques QR et garde-fous anti-abus.
- Autorisation de coûts pour services, tests appareils, stores et paiements.
- Autorisation éventuelle de fusion/déploiement : **jamais implicite**.

## Protocole de synchronisation
- Code, SQL, CI, styles : propriété exclusive des agents Claude.
- Exigences et recettes : propriété GPT dans `docs/recette/`, `docs/qa/`, `docs/produit/`, `docs/commercial/`.
- `docs/PILOTAGE.md` est partagé par sections ; GPT-01 ne créera pas/modifiera la section CLA-01.
- Les constats techniques sont remontés en commentaire sur la PR concernée. Les documents seuls ne constituent pas des tests exécutés.
