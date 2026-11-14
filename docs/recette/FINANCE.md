# COVI — Référentiel financier indépendant (GPT-05)
**Statut : calculs attendus, non exécutés ; règles à confirmer avec le propriétaire avant modification métier.**
Devise : XAF / FCFA. Ce document concerne le **pilotage**, pas la comptabilité réglementaire ni un bénéfice fiscal.
Source examinée : PR #64, `20261024095000_salon_pro_reports.sql`, qui calcule le CA d'origine à partir des lignes payées non remboursées, mais date paiements et remboursements séparément.

## FIN-001 — Vente Boutique : distinguer vente, marge et stock
- Achat affecté à une unité fictive : 4 000 ; prix vendu : 7 000 ; quantité : 2.
- Chiffre d'affaires = **14 000** ; coût des unités vendues = **8 000** ; marge brute = **6 000**.
- Si 1 000 de charges non incluses dans le coût : résultat de pilotage = **5 000**.
- Vérifier que le coût d'un ballon de friperie **non ventilé** ne génère pas artificiellement un coût unitaire ni un bénéfice net supposé.

## FIN-002 — Salon : CA, coûts, commissions, charges
Données fictives payées dans la même période :
- Prestation : 12 000 ; coût direct : 2 000 ; commission 10 % du montant net = 1 200.
- Produit vendu : 6 000 ; coût d'achat : 3 000 ; aucune commission additionnelle.
- Charge non liée aux commissions : 1 500.

Attendus :
- CA prestations 12 000 + produits 6 000 = **18 000**.
- Coûts directs 2 000 + coûts produits 3 000 = **5 000**.
- Marge brute = **13 000**.
- Commissions dues = **1 200**.
- Résultat de pilotage estimé = 18 000 − 5 000 − 1 200 − 1 500 = **10 300**.
- Encaissements nets avant remboursement = **18 000**, si la totalité est reçue sur la période.
- Une commission **due** n'est pas nécessairement **versée** : ne pas la déduire deux fois de la trésorerie.

## FIN-003 — Paiement mixte / idempotence
Ticket 18 000 encaissé en espèces 10 000 + Mobile Money 8 000 (validation manuelle).
- Paiements cumulés = **18 000** ; encaissements nets = **18 000**.
- Relance avec la même clé : **0** encaissement supplémentaire ; **0** commission supplémentaire ; **0** débit de stock supplémentaire.
- Une référence externe absente n'est pas une preuve de confirmation de l'opérateur.

## FIN-004 — Remboursement entre deux mois : décision P0
Opération : prestation payée **12 000 le 28/09** ; remboursement intégral **12 000 le 05/10**.
**Recommandation de pilotage à soumettre au propriétaire :**
- Septembre reste figé : CA réalisé **+12 000** ; encaissement **+12 000**.
- Octobre : ajustement commercial **−12 000** identifié comme remboursement d'une prestation de septembre ; décaissement **−12 000**.
- Cumul septembre + octobre après remboursement : CA net **0**, flux net **0** avant autres coûts.

**Risque observé dans la SQL de la PR #64 :** `salon_report` filtre `l.refunded_at is null` sur les lignes d'origine. Le remboursement d'octobre peut ainsi **faire disparaître rétrospectivement** la vente du rapport de septembre, tandis que la sortie de trésorerie apparaît en octobre. Ce traitement doit être arbitré et spécifié explicitement, pas corrigé silencieusement. Les coûts directs, commissions et éventuels retours doivent être rapprochés sans double comptage.

Option alternative à étudier : rapport de CA rétrospectif net corrigé, avec version figée des clôtures et état séparé des corrections. Dans les deux cas, afficher la méthodologie et permettre la réconciliation sur deux mois.

## FIN-005 — Commissions et dépenses
Une commission de 1 200 due puis versée :
- Compte de résultat de pilotage : **une seule charge commission de 1 200**.
- Flux de trésorerie : **une seule sortie de 1 200 à la date de versement**.
- Si une charge saisie porte déjà la catégorie « commission », elle ne doit pas générer une seconde déduction sans justification et rapprochement.

## FIN-006 — Remboursement partiel et stock
Ticket total 18 000, remboursement d'une ligne produit 6 000 :
- Encaissements nets = **12 000** sur l'ensemble des périodes pertinentes.
- Si remise en stock autorisée : +1 unité au produit ; les consommables **utilisés** sur une prestation ne reviennent pas automatiquement.
- Commission et coût des lignes conservées inchangés, ajustement de la ligne remboursée conforme à la décision FIN-004.

## Méthode de recette
Exécuter les scénarios en préproduction isolée, comparer requêtes, événement de vente, encaissement, coût, commission, remboursement et résultat affiché. CLA-03/CLA-05 exécutent ; GPT-05 contrôle indépendamment les écarts. Aucun montant réel ni identifiant client personnel.
