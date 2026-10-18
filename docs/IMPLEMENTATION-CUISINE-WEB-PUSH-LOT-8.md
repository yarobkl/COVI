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
- Supabase Edge : `COVI_KITCHEN_VAPID_PUBLIC_KEY` et `COVI_KITCHEN_VAPID_PRIVATE_KEY`, générées en paire par l'outillage Web Push; la clé privée doit rester secrète.
- Supabase Edge : `COVI_KITCHEN_VAPID_SUBJECT`, adresse mail de contact sous forme `mailto:`.
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

## Revue supplémentaire — 18 octobre 2026

- La regex de la clé Web Push est bornée à 255 caractères **dans la RPC, la contrainte PostgreSQL et le dispatcher**. La correction historique de l'erreur PostgreSQL `invalid repetition count(s)` est bien présente dans GitHub.
- L'Edge Function n'accepte plus qu'une en-tête `Authorization: Bearer <secret>` correctement formée, et reste désactivée si la configuration manque.
- Un **endpoint de navigateur ne peut appartenir qu'à un compte/restaurant à la fois** : la reconnexion sur un autre établissement déplace l'abonnement et initialise le curseur de ce nouvel établissement. Une reconnexion du même compte conserve son curseur. Cela évite les alertes croisées en cas d'appareil partagé.
- Les tests SQL contrôlent le passage d'un endpoint d'un restaurant à l'autre, sans recourir à la base réelle; les tests Node couvrent la clé invalide et l'en-tête d'authentification.
- Les secrets de VAPID et de cron restent uniquement côté Edge ou Vault. Aucune valeur secrète n'est enregistrée dans le dépôt.
- **Reste à valider en préproduction** : arrivée d'un vrai Web Push à un téléphone hors application, redémarrage de navigateur, expiration des abonnements, limites des OS et tableau de bord des erreurs.

## Ordonnanceur sécurisé — mode d'emploi pour une future préproduction seulement

**Ne pas exécuter le SQL ci-dessous sur le projet de production.** Le cron n'est pas installé, et `COVI_KITCHEN_PUSH_ENABLED` doit rester absent ou `false`. Faire valider séparément la configuration d'un projet Supabase de préproduction isolé, ses permissions, ses migrations, son pare-feu et sa procédure de retour arrière.

1. Générer une paire VAPID et un secret d'invocation aléatoire de 32 octets minimum **en dehors du dépôt**. Configurer `COVI_KITCHEN_VAPID_PUBLIC_KEY`, `COVI_KITCHEN_VAPID_PRIVATE_KEY`, `COVI_KITCHEN_VAPID_SUBJECT`, `COVI_KITCHEN_PUSH_DISPATCH_SECRET` sur la fonction Edge de préproduction, sans les imprimer dans les logs.
2. Enregistrer dans Supabase Vault une URL HTTPS **fixe et vérifiée** de la fonction de préproduction (nom `covi_kitchen_push_url`) et le même secret d'invocation (nom `covi_kitchen_push_dispatch_secret`). Ne jamais mettre de secret en clair dans l'instruction cron.
3. Installer `pg_cron` et `pg_net` sur la seule base isolée. Vérifier que seule une personne autorisée peut lire les secrets Vault et modifier les jobs. Tester d'abord l'invocation manuelle avec le service **désactivé**, qui doit renvoyer HTTP 503 sans réclamer de travaux.
4. Une fois tous les prérequis et tests validés, **et seulement dans la préproduction**, créer ce job par une session PostgreSQL privilégiée :

```sql
-- EXEMPLE PRÉPRODUCTION SEULEMENT. NE PAS EXÉCUTER EN PRODUCTION.
select cron.schedule(
  'covi-kitchen-push-staging',
  '* * * * *',
  $job$
    select net.http_post(
      url := (select decrypted_secret from vault.decrypted_secrets
              where name = 'covi_kitchen_push_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select decrypted_secret
          from vault.decrypted_secrets
          where name = 'covi_kitchen_push_dispatch_secret')
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 90000
    );
  $job$
);
```

5. Sur cette préproduction, activer `COVI_KITCHEN_PUSH_ENABLED=true` seulement le temps de la recette : tester 401 sans Bearer, 503 en mode désactivé, 200 avec secret et jobs valides, expiration 404/410, échecs 5xx, reprises de bail et absence de notification croisée.
6. Consulter `cron.job_run_details`, les statuts des requêtes `pg_net` et les logs de la fonction (sans données client ni secrets). Une exécution cron réussie ne garantit **pas** qu'un Push a été distribué : contrôler les accusés serveur et la réception des appareils.
7. Procédure de désactivation : mettre `COVI_KITCHEN_PUSH_ENABLED=false`, puis `select cron.unschedule('covi-kitchen-push-staging');` sur la préproduction. Ne jamais traiter un événement Push comme une preuve de préparation, service ou encaissement.

Documentation Supabase : https://supabase.com/docs/guides/functions/schedule-functions et https://supabase.com/docs/guides/cron/quickstart

## Prérequis de compatibilité appareil

- **iPhone/iPad** : iOS/iPadOS 16.4 ou version ultérieure, PWA ajoutée à l'écran d'accueil, permission déclenchée par une action de l'utilisateur et origine HTTPS. Vérifier le bon Service Worker et la réception après fermeture avec un appareil réel.
- **Android** : navigateur prenant en charge Push API + notifications autorisées par Android; limitations de batterie et restrictions d'arrière-plan susceptibles de retarder les avis.
- **Windows, macOS et Linux** : navigateur compatible, autorisation système et navigateur, politique d'économie d'énergie et service Push accessible. Faire un essai avec la fenêtre fermée et un autre après reconnexion.
- Une PWA retirée de l'écran d'accueil, une permission révoquée ou un endpoint 404/410 impose une nouvelle souscription via le bouton utilisateur. Aucune garantie de livraison temps réel.

## Résilience réseau et changement de rôle — revue du 18 octobre

- L'Edge Function applique un délai de 5 secondes aux appels PostgREST et une temporisation de socket de 8 secondes aux envois Web Push ; la dernière limite est un délai d'inactivité réseau, **pas une garantie de temps total maximum**.
- Le dispatcher réclame un lot de 5 abonnements au maximum par appel, afin de réduire les risques de dépassement du bail SQL de 90 secondes et de l'expiration HTTP du cron. Le nombre de destinataires en attente peut être supérieur à 5 et sera servi sur les invocations suivantes.
- Le cron de préproduction (non installé) laisse 90 secondes de délai HTTP; une livraison lente ou interrompue n'est jamais enregistrée comme effectivement livrée sans accusé de la fonction SQL.
- Le passage d'un employé Cuisine au rôle Service désactive ses abonnements Push côté PostgreSQL dans la même transaction, même si son compte reste actif.
- Les URL Push contenant identifiants ou ports explicites sont rejetées par SQL dès la souscription; le dispatcher vérifie lui aussi les destinations pour empêcher les appels vers des hôtes non approuvés.
- La recette réelle doit vérifier une reprise après panne, l'expiration de bail et l'éventualité de doublons lorsque le fournisseur accepte un envoi mais que l'accusé SQL échoue.
