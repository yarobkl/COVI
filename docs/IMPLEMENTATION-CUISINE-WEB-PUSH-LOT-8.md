# COVI — Restaurant : Web Push Cuisine (lot 8, branche de validation)

**Date : 18 octobre 2026**. Branche `feature/covi-restaurant-salon-v1`, PR 44 en brouillon.

## Fonctionnement

1. Un cuisinier authentifié sélectionne son restaurant COVI et demande lui-même les notifications. Son navigateur doit les autoriser.
2. Le site enregistre l'abonnement Push de **cet appareil et de ce compte** par la RPC `restaurant_kitchen_push_register`, qui vérifie à nouveau le magasin, le rôle et l'activité de l'employé.
3. PostgreSQL conserve une ligne par abonné et un curseur de livraison; un déclencheur existant écrit un événement lorsque la commande est envoyée. Aucune donnée personnelle des clients ne quitte la base.
4. Une Edge Function `restaurant-kitchen-push` s'exécute **uniquement sur invocation serveur authentifiée**. Elle réserve atomiquement les événements courants par appareil et vérifie les clés VAPID. Son message est générique (« De nouvelles préparations attendent la cuisine »).
5. Les livraisons en erreur reprennent après temporisation, avec bail de 90 secondes et délai exponentiel. Une réponse 404/410 du prestataire désabonne l'appareil. Une nouvelle tentative peut parfois générer une notification similaire après panne de réseau; le navigateur utilise un tag stable pour regrouper ces avis.
6. À sa déconnexion, un employé tente de se désabonner; la désactivation administrative supprime également ses abonnements en base. Chaque envoi vérifie les droits **à nouveau**.
7. Le système de suivi et d'accusé de lecture dans COVI demeure la source de vérité. Recevoir ou cliquer sur une notification n'encaisse pas, ne sert pas, ne valide pas, et ne modifie aucune commande.

## Secrets et conditions de déploiement ultérieur

**Ne saisir aucune valeur réelle dans le code ou un commit GitHub.**

- Supabase Edge : `COVI_KITCHEN_PUSH_ENABLED=true` (laisser absent/false tant qu'aucun test de préproduction n'a réussi).
- Supabase Edge : `COVI_KITCHEN_PUSH_VAPID_PUBLIC_KEY` et `COVI_KITCHEN_PUSH_VAPID_PRIVATE_KEY`, générées en paire par l'outillage Web Push; la clé privée doit rester secrète.
- Supabase Edge : `COVI_KITCHEN_PUSH_VAPID_SUBJECT`, adresse mail de contact sous forme `mailto:`.
- Supabase Edge : `COVI_KITCHEN_PUSH_DISPATCH_SECRET` (au moins 32 caractères aléatoires, indépendant de la clé Supabase).
- Variables publiques front : `VITE_COVI_KITCHEN_VAPID_PUBLIC_KEY` égale à la clé publique ci-dessus. **Jamais** la clé privée.
- Variables Supabase existantes `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` accessibles seulement au processus Edge.
- Prévoir ensuite une invocation cron HTTPS sécurisée avec `Authorization: Bearer <secret>`, à intervalle adapté (par exemple une fois par minute), **après autorisation de déploiement**. Le cron n'est pas configuré par ce lot.

`supabase/config.toml` positionne `verify_jwt=false` **parce que cet appel est serveur à serveur**. L'Edge Function refuse elle-même tout appel dépourvu du secret prévu. Elle est désactivée par défaut.

## Compatibilité et cas limites

- iPhone/iPad : la réception des notifications Push sur navigateur dépend d'une **web app ajoutée à l'écran d'accueil** et de l'autorisation utilisateur sur version iOS/iPadOS compatible.
- Android et ordinateur : permission navigateur et abonnement au Push Service du fournisseur, sur origine HTTPS.
- Même lorsque le push est disponible, batterie, OS, réseau et politiques navigateur peuvent retarder les alertes. **Aucune promesse de livraison instantanée ni garantie**.
- Révocation d'un compte, utilisateurs de plusieurs commerces, appareils différents, permissions refusées et terminaux déconnectés doivent être testés sur matériels réels.
- Aucun site client ni aucune table d'un autre établissement ne peut choisir les destinataires d'une notification.

## Ce que nous n'avons pas fait

**Aucune nouvelle migration appliquée à Supabase production; aucun secret de production configuré; aucune fonction Edge publiée, aucune tâche cron installée, aucune fusion et aucun changement sur Vercel.**

Ce lot doit encore passer la revue de sécurité, les vérifications de l'environnement Edge et une recette réelle multi-appareils avant un déploiement autorisé. La DA « Le Cahier » demeure inchangée.
