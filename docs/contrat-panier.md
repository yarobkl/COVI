# Contrat : vente multi-articles (`record_cart_sale`)

Destinataires : l’écran Vendre et la file hors connexion. Ce document est le contrat entre le
client et la base. La fonction vient de la migration
`supabase/migrations/20261010100000_record_cart_sale.sql`. Les tests sont dans `tests/sql/cart.sql`
et `tests/sql/cart_concurrency.sh`.

`record_sale` (vente d’un seul article) ne change pas. Les deux fonctions partagent la même clé
d’idempotence (voir plus bas).

## Signature

```sql
public.record_cart_sale(
  p_shop_id             uuid,   -- boutique de l'utilisateur connecté
  p_items               jsonb,  -- lignes du panier (format ci-dessous)
  p_payment_method      text,   -- 'cash' | 'mobile_money' | 'card' | 'bank_transfer' | 'other'
  p_client_operation_id uuid    -- clé d'idempotence du panier, générée par le client
) returns uuid                  -- id de la vente (public.sales.id)
```

- Exécutable par le rôle `authenticated` seulement : il faut une session Supabase (JWT
  utilisateur). `anon` et `service_role` n’y ont pas accès.
- `SECURITY DEFINER`. La fonction vérifie elle-même que `p_shop_id` appartient à `auth.uid()`.
- Tout ou rien : en cas d’erreur sur une ligne, rien n’est écrit (ni vente, ni ligne, ni stock).

## Format de `p_items`

Un tableau JSON de 1 à 50 objets :

```json
[
  { "product_id": "3f1c…-uuid", "quantity": 2, "sold_unit_price": 4500 },
  { "product_id": "9a7e…-uuid", "quantity": 1, "sold_unit_price": 14000 }
]
```

| Clé               | Type JSON                             | Règle                                                                |
| ----------------- | ------------------------------------- | -------------------------------------------------------------------- |
| `product_id`      | chaîne, uuid `8-4-4-4-12` hexadécimal | Un produit `active` de la boutique. Une seule fois par panier.       |
| `quantity`        | nombre entier                         | > 0. Exactement 1 pour une pièce unique. Au plus le stock.           |
| `sold_unit_price` | nombre                                | ≥ 0, prix unitaire réellement encaissé, en FCFA. Arrondi au centime. |

- Aucune autre clé n’est acceptée. Une faute de frappe comme `qty` est refusée, elle n’est pas
  ignorée.
- Les nombres doivent être des nombres JSON, pas des chaînes (`2`, pas `"2"`).
- Pour vendre deux unités d’un même produit, envoyez une ligne avec `quantity: 2`, pas deux lignes.
- Le total de la vente (`sales.total_amount`) est calculé par la base :
  Σ `quantity × sold_unit_price`. Le client n’envoie pas de total.
- `initial_unit_price` (le prix catalogue au moment de la vente) est lu par la base dans le produit.
- Un panier ne peut pas mélanger des produits de test (`is_test`) et des produits réels. La vente
  est `is_test` si tous ses produits le sont.

## Idempotence : un `client_operation_id` par panier

- Générez **un** uuid (`crypto.randomUUID()`) quand le panier est validé. Stockez-le avec le
  panier dans la file. **Réutilisez-le à chaque nouvel essai** du même panier : au rechargement
  de la page, après une coupure réseau ou après une reconnexion.
- Si une vente existe déjà pour (`p_shop_id`, `p_client_operation_id`), la fonction renvoie
  **l’id de cette vente** sans rien réécrire ni décrémenter. Si une réponse s’est perdue (la vente
  est passée mais le client n’a pas reçu l’id), il suffit de renvoyer le même appel.
- Le contenu n’est pas comparé : c’est la clé qui fait foi. Si un panier différent est envoyé
  avec une clé déjà utilisée, la fonction renvoie la vente existante et ignore le nouveau
  contenu. **Ne réutilisez jamais une clé pour un autre panier.**
- Après une erreur, rien n’est enregistré. La même clé peut donc resservir si le vendeur
  corrige le panier, par exemple en retirant un article épuisé. Une nouvelle clé convient aussi.
- La clé est partagée avec `record_sale` : la même boutique ne peut pas avoir deux ventes avec la
  même clé, quelle que soit la fonction qui les a créées. Deux appels simultanés avec la même clé
  sont traités l’un après l’autre (verrou consultatif) et renvoient le même id.

## Erreurs

Le **message** (`error.message` côté supabase-js) est stable et sert à identifier l’erreur. Il
est en anglais. Le `details` (`DETAIL`) donne la ligne en cause, avec un index qui part de 0 dans
`p_items` (`item 1: product_id …, requested 3, available 2`). Il sert à l’affichage et au
diagnostic. Ne le comparez pas.

- **Réessayable** : le même appel, avec la même clé, peut réussir plus tard sans modifier le
  panier. Gardez le panier dans la file.
- **Définitive** : le même panier échouera toujours. Retirez-le de la file automatique et
  montrez-le au vendeur pour qu’il le corrige ou l’abandonne.

| `message`                                  | SQLSTATE (`code`) | Cause                                                                                                                                                           | Nature                                                                                                    |
| ------------------------------------------ | ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `Authentication required`                  | `42501`           | Pas de session (JWT absent ou expiré).                                                                                                                          | Réessayable après reconnexion                                                                             |
| `Shop not found`                           | `42501`           | La boutique n’existe pas ou n’appartient pas à l’utilisateur connecté.                                                                                          | Définitive. Exception : si un autre compte est connecté, réessayer une fois reconnecté avec le bon compte |
| `Sale operation id is required`            | `P0001`           | `p_client_operation_id` nul.                                                                                                                                    | Définitive (bug client)                                                                                   |
| `Invalid payment method`                   | `P0001`           | Moyen de paiement hors liste.                                                                                                                                   | Définitive (bug client)                                                                                   |
| `Cart items must be a JSON array`          | `P0001`           | `p_items` nul ou pas un tableau.                                                                                                                                | Définitive (bug client)                                                                                   |
| `Cart must contain between 1 and 50 items` | `P0001`           | Panier vide ou de plus de 50 lignes.                                                                                                                            | Définitive                                                                                                |
| `Invalid cart item`                        | `P0001`           | Ligne mal formée : pas un objet, clé manquante ou inconnue, mauvais type JSON, uuid invalide, quantité non entière ou > 2 147 483 647.                          | Définitive (bug client)                                                                                   |
| `Quantity must be positive`                | `P0001`           | Quantité ≤ 0.                                                                                                                                                   | Définitive                                                                                                |
| `Sold price cannot be negative`            | `P0001`           | Prix < 0.                                                                                                                                                       | Définitive                                                                                                |
| `Duplicate product in cart`                | `P0001`           | Le même `product_id` apparaît sur deux lignes.                                                                                                                  | Définitive (fusionner les lignes)                                                                         |
| `Sale total too large`                     | `P0001`           | Total > 999 999 999 999,99.                                                                                                                                     | Définitive                                                                                                |
| `Product unavailable`                      | `P0001`           | Produit inexistant, d’une autre boutique, déjà vendu (`sold`) ou archivé. C’est aussi l’erreur de la pièce unique vendue entre-temps par une autre caisse.      | Définitive                                                                                                |
| `Unique piece quantity must be 1`          | `P0001`           | Pièce unique demandée en quantité ≠ 1.                                                                                                                          | Définitive                                                                                                |
| `Insufficient stock`                       | `P0001`           | Stock du produit < quantité demandée.                                                                                                                           | Définitive                                                                                                |
| `Cannot mix test and real products`        | `P0001`           | Le panier contient des produits de test et des produits réels.                                                                                                  | Définitive                                                                                                |
| `Subscription inactive: shop is read-only` | `P0001`           | Abonnement SaaS du propriétaire de la boutique suspendu, annulé ou échu (trigger `covi_subscription_write_guard`, migration `20261010180000`, branche d'audit). | **Définitive mais à conserver et afficher** : voir « Abonnement inactif » ci-dessous                      |

Erreurs hors de la fonction, toutes **réessayables** avec la même clé :

- réseau coupé, délai dépassé, réponse HTTP 5xx ou absence de réponse. La vente a pu passer :
  rejouer avec la même clé renvoie son id ;
- JWT expiré renvoyé par PostgREST (HTTP 401, `PGRST301` / `PGRST303`). Rafraîchissez la session,
  puis rejouez ;
- `40001` (échec de sérialisation) et `40P01` (interblocage). Ces erreurs ne sont pas attendues
  en lecture validée, le mode de PostgREST, mais elles sont réessayables par nature.

Si plusieurs lignes sont invalides, seule la première erreur est signalée. Les contrôles se font
dans cet ordre :

1. session et boutique ;
2. clé et moyen de paiement ;
3. format du panier, ligne par ligne (y compris les doublons et le total) ;
4. état des produits, ligne par ligne dans l’ordre du panier : disponibilité, puis pièce unique,
   puis stock ;
5. mélange test/réel.

Un panier déjà enregistré (même clé) renvoie son id **avant** l’étape 4. Un rejeu ne peut donc
pas échouer pour « stock insuffisant » à cause de sa propre vente.

## Abonnement inactif (SaaS, PR #12 + correctif d'audit)

Message exact : `Subscription inactive: shop is read-only` — SQLSTATE `P0001`. Le même message est
renvoyé par `record_sale`, `record_cart_sale` et toute écriture directe sur `products`,
`arrivals`, `sales`, `shop_expenses` (et la suppression d'une boutique). Le contrôle porte sur
l'abonnement du **propriétaire de la boutique** au moment où le serveur reçoit l'appel, pas au
moment où la vente a été saisie hors ligne : une vente mise en file pendant que l'abonnement était
actif puis synchronisée après la suspension est refusée (pas de contournement).

Règle de reprise côté client :

1. Ne pas réessayer automatiquement (ce n'est pas une erreur réseau ; le message ne contient
   aucun des mots `fetch|network|offline|timeout|jwt|token|unauthorized|401|not authenticated`).
2. **Ne jamais supprimer la vente en silence** : la retirer de la file active, la conserver avec
   son motif, son `client_operation_id` et son contenu, restaurer le stock local, et l'afficher
   (« abonnement suspendu : vente non enregistrée »).
3. Après renouvellement de l'abonnement, la vente peut être renvoyée **avec la même clé** :
   rien n'ayant été écrit, elle est enregistrée normalement (testé, étape 12 de
   `tests/sql/saas_simulation.sql`).
4. Un rejeu d'une vente **déjà enregistrée** avant la suspension (même clé) renvoie toujours son
   id sans rien écrire : l'idempotence est vérifiée avant le contrôle d'abonnement.

Commerçants V1 sans compte SaaS et premier abonnement jamais payé (`pending_payment`,
`period_start` nul) : aucune restriction. Contexte serveur sans utilisateur (`auth.uid()` nul) :
aucune restriction.

Tests : `tests/sql/saas_simulation.sql` (étapes « 10 Hors ligne » et « 12 Renouvellement ») et
`tests/offline_subscription.mjs` (file hors ligne actuelle de `src/lib/offline.ts`, inchangée :
rejet définitif conservé avec son motif, stock restauré, pas de boucle).

## Concurrence

Les produits du panier sont verrouillés dans l’ordre de leur id. Deux caisses qui vendent en même
temps la dernière pièce sont traitées l’une après l’autre : la première vend, la seconde reçoit
`Product unavailable` (ou `Insufficient stock` si le produit avait plusieurs unités) et rien n’est
écrit pour elle. Deux paniers qui partagent plusieurs produits ne s’interbloquent pas, quel que
soit l’ordre des lignes.

## Exemple supabase-js

```ts
import type { SupabaseClient } from '@supabase/supabase-js'

type CartLine = { product_id: string; quantity: number; sold_unit_price: number }
type PaymentMethod = 'cash' | 'mobile_money' | 'card' | 'bank_transfer' | 'other'

// Erreurs pour lesquelles le même appel (même clé) peut réussir plus tard.
const RETRYABLE_MESSAGES = new Set(['Authentication required'])
const RETRYABLE_CODES = new Set(['40001', '40P01', 'PGRST301', 'PGRST303'])

export async function recordCartSale(
  supabase: SupabaseClient,
  shopId: string,
  lines: CartLine[],
  paymentMethod: PaymentMethod,
  clientOperationId: string, // généré UNE fois à la validation du panier, conservé dans la file
): Promise<{ saleId: string } | { error: string; retryable: boolean; details?: string }> {
  const { data, error } = await supabase.rpc('record_cart_sale', {
    p_shop_id: shopId,
    p_items: lines, // tableau JS : supabase-js l'envoie en JSON
    p_payment_method: paymentMethod,
    p_client_operation_id: clientOperationId,
  })
  if (!error) return { saleId: data as string }
  // Pas de code renvoyé par la base (réseau, fetch échoué) : on rejoue plus tard, même clé.
  const retryable =
    !error.code || RETRYABLE_MESSAGES.has(error.message) || RETRYABLE_CODES.has(error.code)
  return { error: error.message, retryable, details: error.details ?? undefined }
}

// Validation du panier :
// const opId = crypto.randomUUID();      // à stocker avec le panier dans la file
// await recordCartSale(supabase, shopId, [
//   { product_id: p1, quantity: 2, sold_unit_price: 4500 },
//   { product_id: p2, quantity: 1, sold_unit_price: 14000 },
// ], 'mobile_money', opId);
```

Pour relire la vente après coup (lecture autorisée par la RLS) :
`supabase.from('sales').select('id, total_amount, sale_items(product_id, quantity, sold_unit_price)').eq('id', saleId)`.
