# Base de données COVI

COVI s’appuie sur Supabase (PostgreSQL, PostgREST, Auth, Storage). Le schéma vit dans
`supabase/migrations/` : un fichier SQL daté par évolution, appliqué dans l’ordre des noms. Ces
fichiers sont identiques à ce qui est appliqué en production.

## Schéma

| Table           | Rôle                                                                                                                                                          |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `shops`         | Le commerce. Un seul par utilisateur (`owner_id` unique, référence `auth.users`), devise `XAF`.                                                               |
| `arrivals`      | Arrivages : commande fournisseur (`supplier_order`) ou ballon / lot mixte (`balloon`). Coûts, dates, statut `draft → ordered → in_transit → received`.        |
| `products`      | Articles en stock, rattachés ou non à un arrivage. `quantity_on_hand`, `is_unique_piece`, statut `active` / `sold` / `archived`, photo privée (`image_path`). |
| `sales`         | Une vente : boutique, moyen de paiement, montant total, date (`sold_at`), clé d’idempotence `client_operation_id` (file hors connexion).                      |
| `sale_items`    | Lignes d’une vente : produit, quantité, prix initial et prix réellement vendu.                                                                                |
| `shop_expenses` | Charges de fonctionnement (loyer, salaires…), séparées du coût des arrivages.                                                                                 |

`arrivals`, `products`, `sales` et `shop_expenses` portent un drapeau `is_test` : les données de
simulation sont exclues des chiffres par défaut. Photos : bucket privé `covi-product-images`, un
dossier par boutique (`<shop_id>/…`), accessible au seul propriétaire.

## Règles de sécurité

Toutes les tables ont la RLS activée : un utilisateur connecté (`authenticated`) ne voit et ne
modifie que les lignes de sa boutique. Depuis la migration `20261010090000_server_side_sensitive_writes` :

- **Ventes : écriture uniquement par l’RPC `record_sale`.** La fonction est `SECURITY DEFINER`
  (`search_path` vide) et vérifie explicitement que `p_shop_id` appartient à `auth.uid()` avant
  toute lecture. Elle contrôle quantité, prix, moyen de paiement, stock, pièce unique, puis crée
  la vente, sa ligne et décrémente le stock dans la même transaction. Idempotente via
  `p_client_operation_id` (verrou consultatif par boutique et opération).
- **Panier multi-articles : RPC `record_cart_sale`** (migration `20261010100000_record_cart_sale`),
  mêmes garanties que `record_sale` pour 1 à 50 lignes en une seule vente, tout ou rien, produits
  verrouillés dans l’ordre des id. Contrat client (format, idempotence, erreurs) :
  [`docs/contrat-panier.md`](contrat-panier.md).
- `sales` et `sale_items` sont en **lecture seule** pour `authenticated` (droits INSERT / UPDATE /
  DELETE retirés, politiques RLS réduites à `SELECT`). L’historique ne peut plus être modifié ni
  effacé depuis le client.
- `products` : INSERT autorisé (ajout d’article) ; UPDATE limité aux colonnes `name`, `category`,
  `brand`, `size`, `initial_sale_price`, `image_path`, `arrival_id`. `quantity_on_hand` et
  `status` ne changent que par `record_sale`. À la création, un trigger impose `status = 'active'`
  et refuse une pièce unique dont la quantité n’est pas 1 ; la quantité est toujours ≥ 0.
- **Cohérence inter-boutiques** (triggers) : `products.arrival_id` doit désigner un arrivage de la
  même boutique ; `sale_items.product_id` doit désigner un produit de la boutique de la vente.
- **Cycle de vie des arrivages** (trigger) : tout statut est accepté à la création (un ballon
  acheté sur place peut être saisi directement « reçu ») ; ensuite le statut ne peut qu’avancer
  (sauter une étape est permis, revenir en arrière non) ; un arrivage ne change pas de boutique ;
  un arrivage reçu sans date reçoit la date du jour (heure de Brazzaville). La contrainte
  `received_date >= order_date` reste en place.
- **Rôles d’API** : `anon` n’a plus aucun droit sur les tables ni sur les RPC (il n’avait de toute
  façon aucune politique RLS) ; aucun rôle d’API n’a `TRUNCATE`, `TRIGGER` ni `REFERENCES` ; les
  fonctions de trigger (dont `touch_updated_at`) ne sont pas exécutables directement par les
  clients (les triggers continuent de se déclencher : le droit EXECUTE n’est vérifié qu’à la
  création du trigger).

Réglage Auth, hors SQL : activer la **protection contre les mots de passe compromis** (Supabase →
Authentication → Policies / Password security, vérification HaveIBeenPwned). Il ne se configure
pas par migration.

## Fonctions

Toutes les fonctions d’agrégat sont `SECURITY INVOKER` (la RLS de l’appelant s’applique),
`STABLE`, `search_path` vide, exécutables par `authenticated` seulement. Paramètres communs :

- `p_tz text default 'Africa/Brazzaville'` : fuseau IANA dans lequel sont calculés « aujourd’hui »
  et les mois civils (une vente le 1er à 00:30 heure de Brazzaville compte pour le nouveau mois) ;
- `p_include_test boolean default false` : inclure les données `is_test` ;
- `p_at timestamptz default now()` : instant de référence (tests, consultation du passé).

Les montants sont en FCFA. Les fonctions qui renvoient du `jsonb` lèvent `Shop not found`
(SQLSTATE 42501) pour une boutique qui n’est pas celle de l’utilisateur ; les fonctions qui
renvoient une table renvoient alors zéro ligne.

| Fonction                                                                                                                                                  | Résultat                                                                               |
| --------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `record_sale(p_shop_id uuid, p_product_id uuid, p_quantity integer, p_sold_unit_price numeric, p_payment_method text, p_client_operation_id uuid) → uuid` | Enregistre une vente (id de la vente ; même id si l’opération a déjà été enregistrée). |
| `record_cart_sale(p_shop_id uuid, p_items jsonb, p_payment_method text, p_client_operation_id uuid) → uuid`                                               | Enregistre un panier (1 à 50 lignes) en une vente ; voir `docs/contrat-panier.md`.     |
| `create_my_shop(p_name text, p_city text default null, p_country text default 'Congo', p_currency text default 'XAF') → shops`                            | Crée (ou retrouve) la boutique de l’utilisateur.                                       |
| `shop_dashboard(p_shop_id uuid, p_tz, p_include_test, p_at) → jsonb`                                                                                      | Tableau de bord du jour et du mois en cours (détail ci-dessous).                       |
| `shop_monthly_sales(p_shop_id uuid, p_months integer default 3, p_tz, p_include_test, p_at) → jsonb`                                                      | Ventes des `p_months` mois civils complets précédant le mois en cours.                 |
| `arrival_profitability(p_shop_id uuid, p_include_test boolean default false) → table`                                                                     | Rentabilité par arrivage.                                                              |
| `arrival_cost_allocation(p_shop_id uuid, p_include_test boolean default false) → table`                                                                   | Coût de revient estimé de chaque produit.                                              |
| `shop_estimated_profit(p_shop_id uuid, p_from date default null, p_to date default null, p_tz, p_include_test) → jsonb`                                   | Bénéfice estimé réel sur une période.                                                  |

Appel depuis le front : `supabase.rpc('shop_dashboard', { p_shop_id: shopId })`.

### `shop_dashboard`

`{ timeZone, today, monthStart, todaySales, todayCount, todayByPaymentMethod: [{ method, amount }],
monthSales, saleCount, previousMonthStart, previousMonthSales, charges, expensesByCategory:
[{ category, amount }], restAfterCharges, arrivalCost, stock, profitBeforeCharges, profit,
arrivalsInProgress, ordersInProgress, balloonsInProgress, inProgressByStatus: { draft, ordered,
in_transit } }`

- ventes du jour / du mois / du mois précédent : bornes en heure locale `p_tz` ;
- `charges` : charges datées du mois en cours (les charges datées des mois suivants ne sont pas
  comptées) ; `restAfterCharges = monthSales − charges` ;
- `arrivalCost` : arrivages reçus dont la date de réception est dans le mois ; coût =
  `global_cost`, ou marchandise + transport + douane si `global_cost = 0` ;
- `profitBeforeCharges = monthSales − arrivalCost`, `profit = profitBeforeCharges − charges` ;
- `stock` : unités des produits `active` ;
- les ventes « en attente » (file hors connexion) sont dans le navigateur, pas en base.

### `shop_monthly_sales`

`{ timeZone, from, to, months: [{ month: 'YYYY-MM', start, amount, saleCount, topCategories }],
topCategories: [{ category, quantity, amount }] }` — mois sans vente à 0 ; catégories classées
par quantité vendue, catégorie vide = `Autre`, top 5 par mois et sur la période.

### `arrival_profitability`

Une ligne par arrivage, du plus récent au plus ancien : `arrival_id, code, kind, status,
origin_country, supplier_name, order_date, received_date, is_test, cost, revenue, profit,
recovery_percent, remaining_to_recover, sold_units, remaining_units, product_count`.
`recovery_percent = arrondi(revenue / cost × 100)` ; `remaining_to_recover = max(cost − revenue,
0)` (le « reste à récupérer » d’un ballon).

### Bénéfice estimé réel : `arrival_cost_allocation` et `shop_estimated_profit`

Méthode de répartition du coût d’un arrivage `C` (= `global_cost`, ou somme des coûts détaillés)
sur ses produits, avec `u` = unités enregistrées d’un produit (stock restant + unités vendues) :

- **commande fournisseur** : au prorata de la valeur au prix initial —
  coût unitaire = `C × prix_initial / Σ(u × prix_initial)` (si tous les prix sont nuls :
  `C / Σ u`) ;
- **ballon** : `C / nombre de pièces enregistrées`. Chaque nouvelle pièce ajoutée fait baisser le
  coût par pièce, y compris celui des pièces déjà vendues : le bénéfice des mois passés évolue
  tant que le ballon n’est pas entièrement saisi, et converge vers le coût réel ;
- **produit sans arrivage** : coût inconnu (compté 0), ventes signalées dans
  `revenueWithoutCost` ;
- **arrivage sans produit** : non réparti, signalé dans `unallocatedArrivalCost`.

`arrival_cost_allocation` renvoie par produit : `product_id, arrival_id, arrival_kind, method
('price_weighted' | 'per_unit' | 'per_piece' | 'none'), initial_sale_price, registered_units,
sold_units, remaining_units, unit_cost, sold_cost, remaining_cost`.

`shop_estimated_profit` renvoie sur la période locale `[p_from, p_to)` (bornes nulles = sans
limite) : `{ revenue, costOfGoodsSold, grossProfit, charges, netProfit, revenueWithoutCost,
unsoldStockCost, unallocatedArrivalCost }`. Contrairement à `shop_dashboard.profit` (ventes −
arrivages reçus du mois), le coût d’un arrivage n’y est compté qu’au rythme de la vente de ses
articles.

### Performances

Mesuré sur 6 boutiques × 50 000 ventes (RLS active) : `shop_dashboard` ≈ 14 ms ;
`shop_monthly_sales` ≈ 180 ms (3 mois) ; `arrival_profitability` ≈ 390 ms ;
`shop_estimated_profit` ≈ 0,4 à 0,7 s. Index couvrants `sales (shop_id, sold_at) include
(total_amount, is_test)` et `sale_items (sale_id) include (product_id, quantity,
sold_unit_price)`.

## Tests en local

Le banc `tests/sql/run.sh` part d’une base PostgreSQL vierge : il crée les stubs Supabase
minimaux (`tests/sql/bootstrap.sql` : rôles `anon` / `authenticated` / `service_role`, schéma
`auth` avec `auth.users` et `auth.uid()`, schéma `storage` avec `buckets`, `objects` et
`foldername()`), applique toutes les migrations dans l’ordre, puis exécute chaque
`tests/sql/*.sql` (transaction annulée) et chaque script `tests/sql/*.sh` hors `run.sh` (tests à
plusieurs sessions, qui suppriment leurs données à la fin).

```bash
# Cluster PostgreSQL 16 jetable (initdb), détruit à la fin :
tests/sql/run.sh --tmp-cluster

# Ou sur un serveur existant (la base covi_test y est supprimée puis recréée) :
docker run -d --name covi-pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:16
PGHOST=localhost PGUSER=postgres PGPASSWORD=postgres tests/sql/run.sh
```

| Test                  | Couvre                                                                                                                                             |
| --------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `three_months.sql`    | Scénario de trois mois : 143 ventes par l’RPC, idempotence, stock, refus, charges, isolation RLS.                                                  |
| `security.sql`        | Écritures directes refusées, `record_sale` sur la boutique d’un autre, stock non modifiable, inter-boutiques, cycle des arrivages, `anon`.         |
| `cart.sql`            | `record_cart_sale` : panier, total, stocks, idempotence, tout ou rien, pièce unique, doublon, autre boutique, non-propriétaire, test/réel, format. |
| `cart_concurrency.sh` | Deux sessions psql : dernière pièce (un seul panier passe), même clé en parallèle, ordre inverse sans interblocage.                                |
| `aggregates.sql`      | Agrégats du scénario trois mois (494 000 / 986 000 / 854 000 FCFA…), répartition des coûts, fuseau horaire, `is_test`.                             |

La CI (job `test-db` de `.github/workflows/windows.yml`) lance le même script sur un service
`postgres:16` à chaque pull request vers `main`. Ne jamais pointer le script vers la production.

## Appliquer une migration

Ajouter un fichier `supabase/migrations/AAAAMMJJHHMMSS_nom.sql`, faire passer `tests/sql/run.sh`,
ouvrir une pull request. La migration n’est appliquée en production que via la CI / la PR, après
revue.
