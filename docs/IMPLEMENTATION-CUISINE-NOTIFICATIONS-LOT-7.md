# COVI — Restaurant, lot 7 : notifications et file durable Cuisine

**17 octobre 2026 — branche isolée `feature/covi-restaurant-salon-v1` (PR brouillon 44)**

## Problème corrigé

L'ancienne alerte Cuisine comparait seulement les plats visibles dans l'écran.
En cas de rafraîchissement, de déconnexion ou de plusieurs cuisiniers, le message
pouvait ne plus correspondre aux préparations réellement en attente.

## Implémentation

- Chaque ligne passant de « brouillon » à **commandée**, y compris un ajout par
  une serveuse, crée un événement immuable `restaurant_kitchen_events` dans la
  même transaction PostgreSQL. Unique par ligne et par restaurant.
- Les commandes déjà ouvertes lors d'une future migration sont récupérées
  dans la file à condition qu'elles soient encore non servies.
- Les cuisiniers actifs et le propriétaire disposent d'une API privée
  `restaurant_kitchen_inbox(shop_id)`. Aucun client, téléphone invité,
  caissier ou salarié du service ne peut lire les événements Cuisine.
- La file est conservée **côté serveur** et les accusés de lecture appartiennent
  individuellement à chaque compte, via `restaurant_kitchen_receipts`.
  Deux cuisiniers d'un même restaurant peuvent donc avoir des éléments non
  lus différents, mais ne voient jamais ceux d'un autre restaurant.
- La liste ne propose que les articles encore au statut « commandé ».
  Un article annulé ou déjà servi ne déclenche plus d'alerte trompeuse.
- La file est chargée 50 entrées par page au maximum, avec avertissement
  explicite lorsqu'il reste d'autres préparations; l'accusé « J'ai vu » ne
  marque comme lues que les entrées affichées.
- Les événements contiennent numéro de commande, libellé de table, article,
  quantité et date, **jamais** coordonnées des clients, salaires, prix, paiement,
  identifiants invités ou secrets QR.
- Les identifiants d'événements `bigint` sont transmis comme chaînes et
  comparés avec `BigInt` dans le navigateur pour éviter les arrondis.
- L'espace Cuisine synchronise toutes les 10 secondes, au retour sur l'onglet
  et lors de la reconnexion. La file évite qu'un redémarrage de navigateur
  fasse disparaître les préparations non acquittées.
- Un bouton opt-in permet au cuisinier d'autoriser les notifications
  système du navigateur. Un worker dédié affiche et ouvre COVI lorsqu'une
  nouvelle préparation est détectée pendant que la page peut synchroniser.

## Limite explicite — Web Push

**Le push distant quand l'application est complètement fermée, ou quand iOS
suspend l'application en arrière-plan, n'est pas livré dans ce lot.**
Un service worker et la permission navigateur ne suffisent pas à eux seuls.

Pour cette fonction ultérieure, il faudra : des abonnements Push par utilisateur,
terminal et établissement, une clé VAPID gérée secrètement sur serveur,
un expéditeur serveur fiable avec retries et suppression des abonnements expirés,
la révocation lors du départ d'un salarié et des tests sur iPhone PWA installée,
Android et ordinateur. Aucun identifiant client ou paiement dans le payload.
Ne jamais promettre une notification pendant la fermeture complète tant que
ce circuit n'a pas été construit et vérifié.

## Tests attendus

- Envoi de groupe → signalement Cuisine ; panier encore brouillon → aucun signal.
- Ajout après validation par serveuse → nouvel événement Cuisine.
- Service d'une ligne → l'événement n'est plus en attente.
- Reconnexion → mêmes événements tant qu'ils ne sont pas acquittés.
- « J'ai vu » → accusé attaché au seul compte du cuisinier, ne sert pas le plat.
- Refus service, caisse, public, autre restaurant et curseur inventé.
- Réponses validées côté TypeScript, tests du dépassement d'entiers JS,
  dédoublonnage d'alertes et compilation.
- Essais sur plusieurs vrais appareils restent nécessaires.

**Aucune production touchée** : migration non appliquée à la base réelle, PR non
fusionnée et application Vercel inchangée. DA « Le Cahier » conservée.
