# COVI — fidélité visuelle « Le Cahier » et fluidité de la nouvelle caisse

Cette note fixe la direction artistique existante. **Aucune refonte de marque, aucun nouveau kit UI, aucune nouvelle dépendance d'animation.**

## 1. Invariants visuels à conserver

- Papier ivoire et quadrillage Seyès réalisés en CSS (tokens `--paper`, `--grid-fine`, `--grid-strong`, `.seyes`).
- Marge rouge du cahier et encres bleue, noire et rouge uniquement selon leur signification actuelle.
- Polices du projet : Atkinson Hyperlegible (lecture), Courier Prime (montants/reçus), Kalam (notes manuscrites).
- Tickets existants (`Ticket` et `TicketLine`) avec découpe dentelée ; montants en FCFA.
- Boutons `btn--sale` à ombre pleine qui s'enfoncent au toucher ; pas de boutons « dashboard SaaS ».
- Aucun spinner en boucle ni animation spectaculaire autour des paiements ; l'enregistrement a déjà un trait de stylo animé grâce à `[aria-busy]`.
- Aucun changement des routes `App`, `SalePage`, `Root`, de Google/Facebook OAuth ou de `main`.

## 2. Raffinements UI appliqués uniquement à la nouvelle caisse

- La confirmation passe d'une carte générique à une **feuille `sheet`** déjà utilisée dans le système.
- Le montant à encaisser se lit sur une ligne `LedgerRow` comme une ligne de comptabilité.
- Prénom obligatoire, moyen de paiement, référence optionnelle et phrase explicite sur l'absence d'API Mobile Money.
- Le reçu apparaît seulement après une réponse validée du serveur, avec le tampon `Stamp` existant et une note Kalam.
- Aucun composant de cette caisse n'est monté dans la navigation active tant que les RPC ne sont pas déployées et auditées.

## 3. Fluidité et critères techniques

- Durées et courbes depuis `tokens.css` : touche 80 ms, transition 150–220 ms, feuille 320 ms.
- Mouvement léger de l'entrée de reçu via `covi-rise`, sans réanimer le fond quadrillé.
- `prefers-reduced-motion: reduce` déjà respecté globalement dans `base.css` et jamais surchargé.
- Le bouton de confirmation affiche `Enregistrement de la vente…`, reste bloqué pendant l'appel et ne déclenche pas de double validation.
- Les classes sont limitées à `.checkout-confirmation` et `.checkout-receipt` dans `src/styles/app/checkout.css`; le design system reste inchangé.
- En cas de perte réseau, le formulaire affiche l'erreur et permet un nouvel essai avec le même identifiant d'opération, sans présenter un faux reçu.

## Validation avant mise en service

1. Conserver `npm run typecheck`, `npm test`, `npm run lint` et la suite PostgreSQL temporaire au vert.
2. Tester tactilement sur un petit smartphone et au clavier ordinateur : lisibilité, changements d'état, absence de zoom involontaire, absence de débordements.
3. Tester la préférence système « Réduire les animations ».
4. Ajouter ensuite la création de panier avec catégories/quantités/prix négociés en reprenant `Ledger`, `Stepper`, `AmountInput` et les mêmes styles.
5. Ne pas mettre en production tant que les migrations et les permissions ne sont pas approuvées.

**État : composants et styles de la nouvelle caisse sur une branche GitHub dédiée, non intégrés à la caisse actuellement en production.**

## 4. Panier par catégories préparé sur la branche

- `ManualCheckoutBasket.tsx` : une feuille avec catégorie, quantités tactiles, prix négocié par pièce, lignes du panier et total sur `LedgerRow`.
- Aucun SKU, marque, taille, couleur ou prix d'achat par produit requis ; les lignes appartiennent directement aux catégories du stock central.
- Une catégorie peut figurer plusieurs fois à des prix de vente négociés différents ; l'ajout répété au même prix consolide sa quantité.
- `Stepper` borne les quantités à la disponibilité chargée ; cette validation locale n'est **pas** une réservation de stock. La base recontrôle à l'approbation et au paiement.
- `checkoutCategoryStock.ts` lit uniquement la nouvelle table `stock_categories`, sous la boutique et l'environnement TEST/réel demandés, sans fallback vers `products`.
- `ManualCheckoutFlow.tsx` enchaîne la création de commande, l'approbation propriétaire et le formulaire de paiement reçu, avec UUID de création stable après coupure réseau.
- Si le serveur renvoie un montant incohérent, le parcours s'arrête avant la confirmation d'encaissement.
- En cas d'erreur de chargement, on recharge les catégories **sans recharger toute l'application**, pour préserver la fluidité.

### Résultats automatisés (GitHub Actions)

Exécution `COVI isolated branch checks` n° `38267502580` : **124 tests unitaires réussis**, typage TypeScript et ESLint validés ; suite PostgreSQL jetable et scénarios de concurrence réussis.

**Limite majeure :** les composants sont présents uniquement sur la branche `feature/covi-stock-central-omnichannel`. Ils ne sont pas montés dans `App.tsx` ni sur les routes de production. La saisie des commandes publiques QR/social et les comptes vendeurs indépendants du propriétaire demandent encore leur propre sécurité.
