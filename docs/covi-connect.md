# COVI Connect V1 — sites web marchands

**Statut** : API générique de connexion serveur à serveur. La configuration de chaque site
(WooCommerce, Shopify ou sur mesure) est distincte ; aucune association automatique avec une
plateforme tierce n'est implicite.

## Activation et modèle de sécurité

Dans COVI : **Commandes > Sites web**, créer une connexion par boutique et par site HTTPS.
Copier immédiatement la clé `covi_site_...` (visible une seule fois). Une empreinte SHA-256
uniquement est conservée en base. La clé sert uniquement au serveur du commerçant :
**ne jamais** l'inclure dans du HTML, JavaScript public, des captures, ni un dépôt GitHub.
La révocation est immédiate. Une clé ne donne accès qu'à la boutique correspondante.

Base : `https://bmbwmwgfzrijglzcgjut.supabase.co/functions/v1/covi-connect`

Les requêtes marchandes doivent fournir l'en-tête `x-covi-key: covi_site_...`,
exclusivement depuis un backend sans en-tête `Origin`. Aucun JWT COVI utilisateur
n'est requis pour ces requêtes serveur. Limites par connexion/minute :
120 lectures produits, 30 imports de commande, 120 consultations de statut.

## Synchronisation du stock (pull)

`GET /products?limit=100&offset=0`

Renvoie les articles réels, y compris épuisés et archivés (quantité disponible = 0), sans
les articles de simulation. Chaque article possède un identifiant COVI `id`, à enregistrer
dans le catalogue du site pour la correspondance. La pagination utilise `nextOffset`.
Synchroniser régulièrement (par exemple toutes les deux minutes) depuis le serveur du site.
Ce connecteur V1 n'émet pas encore de webhooks push vers des URL arbitraires.

## Envoyer une commande

`POST /orders` Content-Type application/json :

```json
{
  "externalOrderId": "WC-1057",
  "customerName": "Client Exemple",
  "customerPhone": "+242061234567",
  "paymentMethod": "mobile_money",
  "fulfillment": "pickup",
  "lines": [{ "productId": "UUID-DU-PRODUIT-COVI", "quantity": 2 }]
}
```

Les lignes doivent correspondre aux vrais produits COVI du catalogue, jamais à des pièces
d'une autre boutique. 1–20 lignes et 1–20 unités par ligne, sans produit dupliqué.
Les prix sont **calculés exclusivement à partir des prix COVI en XAF**.
`externalOrderId` est unique pour cette connexion : réessayer la même commande renvoie
l'ordre existant sans doublonner les ventes. Si l'article est indisponible, le serveur
renvoie 422.

**IMPORTANT** : L'arrivée de cette commande dans « Commandes reçues » ne signifie ni paiement
réussi ni stock réservé. `status=new`. Le propriétaire doit vérifier le paiement puis
confirmer la vente via le parcours existant de COVI. C'est seulement à cet instant que
les quantités diminuent (atomiquement). Un autre acheteur peut acheter la dernière pièce
entre-temps ; le site doit traiter la confirmation manuelle et les cas de rupture.

`GET /orders?external_id=WC-1057` permet de récupérer le statut
`new / accepted / paid / rejected` pour réconcilier les statuts côté site.

## Contraintes de production

- Une connexion active maximum par site souhaitée; le plafond technique est de 10 par boutique.
- Les identifiants et numéros client sont sensibles : pas de données personnelles dans les logs.
- Pas de service_role dans le frontend ni dans un site client.
- Pas de preuve de paiement dans les messages envoyés par le site.
- Aucune compatibilité WooCommerce ou Shopify prête à installer n'est incluse.
- `verify_jwt=false` sur cette fonction car la gateway vérifie séparément JWT propriétaire
  et clés fortes du serveur du partenaire. Toutes les RPC sensibles appliquent des droits
  explicites et les vérifications de propriétaire.
