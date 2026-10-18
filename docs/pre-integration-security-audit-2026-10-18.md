# COVI — audit de sécurité avant intégration (18 octobre 2026)

**Décision : NE PAS FUSIONNER ni déployer la branche expérimentale.** Les corrections et tests décrits ici restent sur `feature/covi-stock-central-omnichannel`.

## Sources vérifiées

- Production `covi-snowy.vercel.app`, inspectée directement par Vercel : branche `claude/caisse-multi-caissiers`, commit `2e48893ad0d5171c51c6f316814961260a4a218c`, déploiement `dpl_BbKKN3t6m3pz8T2Ph5UhuCpcmYxR` état `READY`.
- Branche expérimentale `feature/covi-stock-central-omnichannel` distincte, en avance sur `main` mais **derrière de plusieurs commits** ; `main` n'est pas nécessairement le code actuellement déployé.
- Vérification ciblée des RPC SQL en brouillon, de la passerelle `supabase/functions/public-checkout/gateway.mjs` et des contrôles d'authentification/PIN sur les deux branches.
- L'application de production possède déjà sa propre caisse multi-caissiers, ses commandes publiques, ses fonctions Supabase et son mode comptoir. **Ne pas créer une deuxième caisse en parallèle.**

## Correctifs effectués sur la branche expérimentale

### 1. Quotas par source contournables en changeant de jeton — corrigé

**Avant** : la passerelle calculait `sourceDigest = HMAC(secret, source + publicToken)`. Pour une même source, changer de jeton UUID renouvelait le quota de requêtes et créait de nouvelles fenêtres SQL. Avec des jetons aléatoires, il devenait possible d'exercer une forte pression sur la base.

**Après** : le digest de source est stable entre les jetons ; le digest de lien reste distinct ; trois quotas globaux ont été ajoutés **avant** les autres requêtes privilégiées : 1 200/min pour les catalogues, 1 200/min pour les suivis et 300/min pour les nouvelles demandes. Les valeurs et les nouvelles sortes sont codées côté PostgreSQL dans `draft_public_order_channels.sql` ; le navigateur ne choisit jamais son plafond.

**Preuves prévues** : tests JavaScript pour changements répétés de jetons et d'en-têtes d'IP ; test SQL `tests/postgres/gateway-global-limits.sql` pour vérifier les plafonds et l'interdiction de dépasser la limite. Le runner jetable lance ce nouveau test.

**Limite** : un en-tête `Origin` ou `X-Forwarded-For` n'est pas une identité fiable pour un client non navigateur. Les quotas globaux bornent les ressources, mais ils peuvent aussi être épuisés par un attaquant et perturber la disponibilité. L'attestation Turnstile, les protections d'entrée réseau et la surveillance restent nécessaires.

### 2. Cohérence des contraintes et formatage — corrigée

Lors du premier run du correctif, le test SQL échouait sur `checkout_gateway_rate_windows_bucket_kind_check` car les nouveaux types de quotas n'étaient pas autorisés par le `CHECK` de la table. La contrainte a été mise à jour. Le contrôle Prettier a également repéré `tests/public-checkout-gateway.test.mjs`, désormais formaté par le workflow dédié. **Ne pas considérer ces corrections comme validées tant que la dernière suite complète n'a pas terminé avec succès.**

## Bloquants avant toute mise en service

1. **Compatibilité de production** : intégrer uniquement les différences nécessaires dans une branche créée depuis `claude/caisse-multi-caissiers`. Jamais de fusion globale de la PR expérimentale #22.
2. **Authentification et caissiers** : la caisse existante emploie un mode comptoir avec PIN personnel sur un compte de gestion partagé. Le PIN attribue les ventes mais **n'isole pas** les privilèges si un caissier possède les identifiants du compte de gestion. Évaluer une authentification dédiée/les droits serveur sans modifier brutalement la connexion existante.
3. **Concurrence et comptabilité** : comparer les RPC et le stock de la production aux prototypes avant tout transfert ; vérifier la conservation de l'historique financier et des factures.
4. **Passerelle réelle** : confirmer l'instance de déploiement, les secrets non exposés, la protection du réseau, les limites de charge, les autorisations des RPC et les règles de rejet en cas de panne. Les tests locaux ne remplacent pas le contrôle de l'application hébergée.
5. **Données privées** : définir la durée de conservation, la purge des fenêtres de quota, les règles de suppression des photos et coordonnées clients, et l'accès du commerçant aux références privées.
6. **Tests finaux** : GitHub Windows/format, TypeScript, lint, tests unitaires, PostgreSQL 17 isolé, Supabase Auth/PostgREST local, intégration des PDF, parcours mobile. Consulter l'état du dernier commit : les statuts plus anciens ne suffisent pas.
7. **Autorisations** : accord explicite pour toute migration, fusion vers la branche réellement déployée ou déploiement Vercel.

## Invariants métier et DA

- Aucun paiement Mobile Money n'est automatiquement considéré comme reçu sans vérification effective de l'opérateur ou confirmation explicite du vendeur.
- Le prénom du caissier et l'identité du compte autorisé sont archivés ; le client ne peut confirmer lui-même.
- Le stock est décrémenté **exactement une fois** seulement au paiement confirmé.
- « Le Cahier » (papier, stylo, marge, ticket) et la navigation fluide restent inchangés.
- COVI et GaspardNZ demeurent actifs, sans nouveau coût Supabase.

**État des modifications :** corrections et tests enregistrés sur la branche expérimentale uniquement ; aucun déploiement, fusion ni application de SQL en production.
