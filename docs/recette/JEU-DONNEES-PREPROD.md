# COVI — Oracle de données fictives pour la préproduction (GPT-02/03/04/05)

**Source examinée :** `supabase/preprod/seed_retail_restaurant.sql` et `seed_salon.sql`, branche `integration/preprod` (24/10/2026). **Statut : valeurs calculées à partir du code, PAS mesures sur une base exécutée.**
**Cible autorisée exclusivement :** `stcsjwxmmxnjwisqkudz`. Ne jamais lancer ces opérations sur `bmbwmwgfzrijglzcgjut`.

## 1. Contrôle préalable — blocage potentiel du seed
Le seed Retail insère cinq produits avec `status = 'available'`. Le type applicatif `ProductStatus` est `active | sold | archived`, et `listProducts` sélectionne `status = 'active'`. Les contraintes réelles de la DB de test doivent être vérifiées avant tout lancement ; en l'état, les insertions risquent un échec de contrainte ou une disparition des articles de l'écran Vendre.

Les inserts `auth.users(id)` créent des identités techniques dépourvues d'identifiants de connexion. La création ultérieure de comptes de test n'attribue pas automatiquement ces UUID : démontrer la liaison entre comptes créés via Supabase Auth et `shops.owner_id` avant les scénarios E2E.

Propriétaires de correction : **CLA-02 / CLA-03**, voir issue **#68**. GPT ne modifie ni le seed ni la configuration.

## 2. Boutique « Boutique Élégance (test) »
Si le seed est validé et exécuté en entier :

| Élément | Valeur attendue |
| --- | --- |
| 5 produits fictifs | Robe pagne wax, Chemise lin, Sac à main cuir, Boubou brodé, Sandales tressées |
| Première vente | Robe : 1 × 18 000 + Chemise : 2 × 12 000 = **42 000 XAF**, espèces |
| Deuxième vente | Sandales : 1 × 9 000 = **9 000 XAF**, Mobile Money |
| **Total ventes** | **51 000 XAF**, 2 tickets |
| Stock Robe | 5 → **4** |
| Stock Chemise | 8 → **6** |
| Stock Sandales | 10 → **9** |
| Pièce unique Sac | 1 (non vendue) |
| Boubou | 2 (non vendu) |

Les 51 000 XAF sont du **CA/encaissement brut**, pas un bénéfice : le seed ne renseigne pas les coûts réels de chaque produit. Comparer les ventes et leurs postes à la requête serveur, non seulement à l'écran.

## 3. Restaurant « Le Maquis Bantou (test) »
- Tables : **6**, T1 à T6 ; 4 en salle, 2 en terrasse, si le script passe.
- Carte : **5** articles, dont 3 plats/accompagnements et 2 boissons.
- Articles et prix : Poulet DG 6 500 ; Poisson braisé 7 000 ; Saka-saka 2 000 ; Primus 1 500 ; Jus de gingembre 1 000 (XAF).
- Démonstration à tester après seed : T1 commande 1 Poulet DG + 1 Saka-saka + 2 Jus = **10 500 XAF** ; paiement et transitions selon capacités actuellement disponibles.
- Le seed ne prouve aucun parcours de commande/paiement Restaurant : pas de PASS sans vrai test E2E.

## 4. Salon « Salon Beauté Divine » : oracle financier cumulatif

**Sous réserve que le seed entier réussisse et sans données supplémentaires de tests.** Les dates des notes sont décalées dans le script ; contrôler les **sommes toutes périodes confondues**, pas uniquement « aujourd'hui » ou « ce mois ».

| Note fictive | Détail | Recette XAF | Moyen | Commission XAF |
| --- | --- | ---: | --- | ---: |
| Ticket 1 | Tresses | 25 000 | Espèces | 6 250 (Paul 25 %) |
| Ticket 2 | Coloration + huile capillaire | 15 000 + 6 000 = 21 000 | Mobile Money | 3 000 (Awa 20 % sur prestation) |
| Ticket 3 | Coupe homme | 3 000 | Espèces | 1 000 (Junior fixe) |
| Ticket 4 | Tresses | 25 000 | Mobile Money | 6 250 |
| Ticket 5 | Coloration | 15 000 | Espèces | 3 000 |
| Ticket 6 | Coupe homme | 3 000 | Mobile Money | 1 000 |
| **Total** | **6 tickets réglés** | **92 000** | Espèces 43 000 / Mobile Money 49 000 | **20 500** |

**Coûts directs théoriques, selon `salon_ticket_pay` :**
- Tresses : 2 × 4 000 = **8 000** XAF.
- Coloration : 2 × (80 ml × 60 XAF/ml) = **9 600** XAF. Coût unitaire du stock après acquisition fictive : 60 XAF/ml.
- Produit huile : 1 × 3 500 = **3 500** XAF (coût d'achat fictif).
- **Coûts directs totaux : 21 100 XAF**.
- **Marge brute : 92 000 − 21 100 = 70 900 XAF**.
- **Commissions dues : 20 500 XAF** (ne pas assimiler à « versées »).
- Autres charges : loyer **80 000** + électricité **15 000** = **95 000 XAF**.
- **Résultat de pilotage estimé : 70 900 − 20 500 − 95 000 = −44 600 XAF**.
- Achats de consommables/produits enregistrés : (1 000 × 60) + (3 × 3 500) + (400 × 8) = **73 700 XAF**.
- Sans paiement de commission ni remboursement, flux de trésorerie estimé : 92 000 − 95 000 − 73 700 = **−76 700 XAF** (selon la méthode de la PR #64).

Ce dernier calcul reflète la définition métier actuellement écrite : il n'est **pas** un solde bancaire, et dépend de l'absence de dépenses/corrections supplémentaires.

**Autres attendus si le script est exécuté une seule fois :**
- 3 collaborateurs de référence, 6 prestations, 3 fiches clients.
- 10 rendez-vous fictifs annoncés par le script, à confirmer en base.
- 1 ticket ouvert de **5 000 XAF**, exclu du CA réalisé.
- Il faut vérifier en base que chaque note réglée a des lignes, un paiement, des mouvements de stock et des commissions cohérents.

## 5. Scénarios négatifs sur l'intégrité des données
- Relancer les seeds : **aucun doublon** de ticket ou de dépense (étudier le comportement des gardes `if exists` et `on conflict do nothing`).
- Tester un seed échoué au milieu : constater le rollback effectif, avant tout redémarrage ; ne pas masquer un état partiellement initialisé.
- Comparer coût moyen pondéré, quantité réellement consommée et montant des achats de produits avec les lignes de mouvement.
- Vérifier que comptes B / coiffeur fictif ne voient ni clients ni recettes du salon A.
- Les données d'exemple ne doivent jamais alimenter des dashboards présentés comme résultats commerciaux réels.

## 6. Livrable attendu de CLA-02 / CLA-03 / CLA-05
Pour chaque total : version de `integration/preprod`, Reference ID cible, compte fictif utilisé, extrait de requête **sans secret**, valeur attendue, valeur observée, PASS/FAIL/BLOQUÉ. Si un calcul varie, expliquer la règle serveur et l'écart avant de changer le seed.

**Ce document est un oracle de recette indépendant, pas une preuve de tests exécutés.**
