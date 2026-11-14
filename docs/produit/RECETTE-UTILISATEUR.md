# COVI — Parcours de recette manuel pour le propriétaire (GPT-07)
**Document préparatoire.** Ne pas utiliser sur le site public ni sur la base de production. Exécuter seulement quand CLA-02 et CLA-07 auront fourni **une URL de préproduction vérifiée** associée exclusivement à `stcsjwxmmxnjwisqkudz`.

## Avant tout essai
1. Le responsable technique affiche le **Reference ID effectif du backend** connecté à la version testée, sans montrer de secret : **`stcsjwxmmxnjwisqkudz`**.
2. Le testeur dispose de comptes et données totalement fictifs ; aucun numéro réel, aucune vraie transaction Mobile Money, aucun moyen de paiement réellement débité.
3. La branche/commit testé est indiqué dans la fiche d'essai ; `main` et `bmbwmwgfzrijglzcgjut` ne doivent pas être modifiés.
4. Les agents Claude confirment que tous les rôles et migrations nécessaires sont installés sur cette cible.
5. En cas d'erreur inconnue ou d'environnement ambigu : **arrêt immédiat des écritures**, puis diagnostic CLA-02.

## Parcours guidé
| Étape | Action à faire sur un compte fictif | Contrôle observable |
| --- | --- | --- |
| 1 — Boutique | Ouvrir une boutique fictive et recevoir 3 unités d'un article à 5 000 XAF | Stock initial 3, fiche produit visible |
| 2 — Vente | En vendre 2 à 5 000 XAF | Ticket 10 000 XAF ; stock restant 1 ; historique présent |
| 3 — Reprise | Actualiser l'historique ou rouvrir le ticket | Pas de vente dupliquée ; chiffres cohérents |
| 4 — Restaurant | Ouvrir une table, ajouter deux plats à 4 500 XAF | Total 9 000 XAF ; commande visible au service |
| 5 — Restaurant QR | Scanner le QR de cette table sur téléphone | Le bon restaurant/la bonne table ; aucune donnée interne |
| 6 — Salon | Enregistrer deux RDV simultanés chez deux coiffeurs fictifs différents | RDV distincts sans blocage croisé |
| 7 — Salon caisse | Encaisser une prestation fictive à 12 000 XAF | Note payée et rapport actualisé ; aucun débit réel |
| 8 — Rapport | Comparer vente Salon 12 000, commissions et coûts au détail du rapport | Ne pas présenter le CA comme le bénéfice ; expliquer les charges |
| 9 — Contrôle multi-établissement | Se connecter au compte de la boutique B | Impossible d'ouvrir ou modifier les opérations de A |
| 10 — Mobile | Répéter les tâches principales sur largeur d'écran 390 px | Boutons utilisables, montants et références visibles |

## Pièces à enregistrer
Pour chaque étape : numéro du scénario RET/RES/SAL/FIN, date et commit, résultat attendu, résultat observé, capture masquant les informations privées, et code PASS/FAIL/BLOQUÉ. Ne jamais partager de JWT, de clé Supabase secrète ou de données personnelles.

## Critères d'arrêt
- Application pointant vers un projet autre que `stcsjwxmmxnjwisqkudz` ;
- Écriture effectuée dans la production ;
- Écart de stock ou de caisse inexpliqué ;
- Donnée d'un autre établissement visible ;
- Chiffres d'un mois clos modifiés par un remboursement sans règle approuvée.

Ces étapes sont un **guide de recette**, pas une preuve de tests déjà effectués. Voir `docs/qa/RAPPORT-RECETTE.md` et `docs/recette/FINANCE.md`.
