# COVI — Stock central et caisse omnicanale (spécification validée)

Statut : spécification produit de la prochaine évolution. **Ne constitue pas une implémentation.**
Branche de préparation : `feature/covi-stock-central-omnichannel`.
Ne pas modifier l'authentification Google/Facebook, les données historiques, ni la direction artistique « Le Cahier ».

## Principe
Une boutique = **un stock central unique**, alimenté par les réceptions de **ballons** et diminué uniquement lors des ventes confirmées. Les réceptions sont conservées en historique financier, mais le vendeur ne doit jamais gérer plusieurs stocks de ballons distincts.

## Catégories et réception
Catégories simples : chemises, T-shirts, polos, débardeurs, pulls, sweats, gilets, pantalons, jeans, shorts, bermudas, jupes, robes, vestes, manteaux, ensembles, costumes, vêtements de sport, vêtements enfant/bébé, sous-vêtements (boxers, slips, culottes, soutiens-gorge), chaussettes, chaussures (baskets, sandales, bottes, talons), sacs (à main, à dos, pochettes), accessoires (ceintures, casquettes, bonnets, foulards, cravates), linge de maison (draps, couvertures, serviettes), autres catégories personnalisées.
Chaque réception de ballon : coût d'achat global, date, quantités par catégorie, éventuellement charges d'approvisionnement distinctes. Aucun prix d'achat par pièce, aucune obligation de couleur, marque, motif, taille ou qualité.
Réception = augmentation atomique du stock central par catégorie + enregistrement de l'investissement global. Les anciennes réceptions et ventes doivent rester consultables.

## Trois canaux, une caisse
1. QR code permanent de la boutique (même URL que le lien partageable).
2. Lien permanent partagé sur TikTok, Facebook, Instagram, WhatsApp, etc.
3. Saisie manuelle par le caissier pour clients sans smartphone/QR/Internet.

Page client sans compte : téléphone requis pour envoi numérique de facture (indicatif +242 par défaut), nom/prénom facultatifs ; lignes d'articles avec catégorie, quantité, **prix unitaire saisi directement par le client** (prix négocié), mode de paiement déclaré. Pour vente à distance : une ou plusieurs captures d'écran/photos facultatives, commentaire facultatif, choix livraison ou retrait, coordonnées de livraison adaptées. Pas de catalogue produit détaillé obligatoire.
Les images sont privées, limitées en taille/type et consultables uniquement par la boutique autorisée et le demandeur concerné.

## Cycle de commande
- `submitted` : demande reçue, aucune sortie de stock.
- `accepted_reserved` : commerçant vérifie catégories, quantités et prix, accepte ; réservation temporaire avec expiration. Le client doit accepter toute correction du prix.
- `payment_pending` : paiement déclaré, mais non vérifié ; ne jamais traiter comme payé.
- `paid` : caissier confirme réception réelle et moyen de paiement ; une transaction atomique vérifie le stock, enregistre la vente et décrémente **exactement une fois** les quantités, émet un numéro unique de facture/reçu.
- `cancelled`/`expired` : libérer les réservations ; aucune sortie définitive.
- Livraison/retrait : suivi séparé du statut financier.

Le caissier doit pouvoir refuser, corriger, annuler et distinguer les demandes simultanées, avec horodatage, identité de la boutique et piste d'audit. Empêcher les doubles validations et les ventes de quantités négatives. Ne jamais exposer les demandes d'autres clients.

## Factures/reçus
Numéro unique permanent par document, lié à boutique, vente, date, montant, lignes, moyen de paiement réellement confirmé. Réexport conserve le même numéro ; correction/annulation tracée. Page client de suivi : « en attente » puis « paiement confirmé », accès au téléchargement PDF (et éventuellement image/partage). Conserver **strictement** la DA feuille de cahier COVI. Ne pas exposer les numéros clients en URL publique. Pour vente manuelle sans téléphone : vente autorisée, reçu imprimable ; livraison numérique facultative.

## Indicateurs financiers
Afficher quantités reçues, vendues, disponibles par catégorie ; investissements d'approvisionnement cumulés, encaissements, charges, récupérations d'investissement et bilans périodiques.
**Ne pas appeler « bénéfice net » la différence entre ventes encaissées et totalité des achats si du stock reste invendu.** Sans coût d'achat individuel, calcul exact de la marge par article impossible ; prévoir une méthode explicite et transparente de valorisation du stock restant pour les bilans intermédiaires. Bilan définitif du cycle possible une fois tout vendu et charges attribuées.
Les trois canaux alimentent le même stock et le même historique financier.

## Contraintes de migration
- Conserver les données `shops`, `arrivals`, `products`, `sales`, `sale_items`, `shop_expenses` existantes.
- Migration additive, réversible si possible ; jamais suppression de colonnes/tables historiques sans validation et plan de sauvegarde.
- Vérifier RLS et accès public limité aux pages de demandes ; pas de clé service role dans le client.
- Vérifier les comportements offline existants et la synchronisation anti-doublon.
- Tests : ventes concurrentes, stocks insuffisants, expirations, confirmation répétée, paiements non reçus, liens non authentifiés, isolation multi-boutique, confidentialité images/téléphones, conservation du login Facebook/Google.
- Déployer seulement après tests et validation explicite de la nouvelle expérience. Ne pas fusionner cette branche dans `main` avant cela.

## Ordre d'implémentation proposé
1. Inventaire de l'existant et stratégie de migration sans perte.
2. Stock central / catégories / réceptions et tests de compatibilité.
3. Vente manuelle adaptée et caisse de validation.
4. Demandes publiques via QR permanent et lien, RLS, statuts, réservations.
5. Photos/commentaires/livraison pour vente à distance.
6. Facture unique, export fidèle au design, suivi client.
7. Bilan financier, tests complets et déploiement contrôlé.
