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

## Reprise de l'audit — corrections additionnelles du 18 octobre 2026

**Périmètre :** branche expérimentale uniquement. La source Vercel production
`covi-snowy.vercel.app` a été revérifiée en lecture seule : branche
`claude/caisse-multi-caissiers`, commit `2e48893ad0d5171c51c6f316814961260a4a218c`.
La comparaison GitHub révèle une forte divergence (plusieurs centaines de commits
uniques dans chaque sens). **La PR #22 n'est jamais un candidat à une fusion globale.**

### Protections corrigées et documentées

- `supabase/functions/public-checkout/gateway.mjs` : chaque appel privilégié
  à PostgREST est limité à **8 secondes**, la vérification Turnstile à
  **8 secondes**, et l'envoi d'une photo privée à **12 secondes**. Une
  dépendance bloquée entraîne une réponse générique sans fuite de secrets.
  Des tests simulent une dépendance qui ne répond jamais.
- `src/lib/checkoutFeatureFlag.ts` : pour activer le nouveau parcours,
  la variable de fonctionnalité ne suffit plus. Il faut une URL Supabase
  explicite et valide et une **clé publique**. Les clés `sb_secret_`,
  JWT `service_role`, URL non sécurisée ou configuration absente sont
  refusées. Cela bloque l'activation expérimentale avec le fallback de
  production défini pour l'ancienne application.
- `supabase/sql-drafts/draft_public_order_channels.sql` : ajout d'une
  fonction de maintenance `prune_checkout_rate_windows()`, exécutable
  **uniquement par `service_role`**. Elle supprime les anciennes fenêtres
  de limitation de requêtes après 72 heures (empreintes HMAC) et les
  fenêtres de quotas par boutique après 8 jours. Elle ne touche jamais
  aux transactions, reçus, ventes, stocks, photos ni données clients.
  **Cette maintenance n'est pas programmée ou déployée**.
- `tests/postgres/gateway-retention.sql` : contrôle l'absence d'accès
  par `anon` ou `authenticated`, la conservation des compteurs courants
  et de l'historique financier ; intégré au banc PostgreSQL jetable.
- Le workflow temporaire doté de la permission GitHub `contents: write`
  a été supprimé après le formatage des trois fichiers corrigés.

### Décision sur les risques qui subsistent

1. **Bloquant :** brancher la caisse sur la source réelle de production
   uniquement après comparaison *fonctionnelle* avec le système multicaissiers
   existant. Les tables, RPC et routes expérimentales sont une architecture
   alternative et ne peuvent être empilées telles quelles.
2. **Bloquant :** vérifier en staging réel le proxy IP, Turnstile, la fonction
   Edge, la configuration des secrets, les permissions PostgREST et le
   fonctionnement des photos privées. Des tests locaux réussis ne prouvent
   pas l'hébergement distant.
3. **Bloquant :** gestion des comptes partagés et PIN de la caisse réellement
   déployée : un PIN seul ne doit pas fournir une isolation des permissions
   si l'utilisateur possède la session du compte gestionnaire.
4. **À cadrer :** durée de conservation, information des clients, purge des
   téléphones, adresses de livraison et photos, sous réserve des obligations
   légales de conservation des preuves de vente. Le présent changement ne
   définit **aucune purge de données clients**.
5. **À réaliser :** accord explicite du client si le vendeur modifie les prix
   proposés, alignement des rapports financiers catégoriels, accessibilité
   et recette mobile réelle.

**Décision maintenue : NO-GO.** Rien de cette branche n'a été migré,
fusionné ou déployé sur COVI production. Aucun projet Supabase ni
GaspardNZ n'a été suspendu. Toutes les corrections présentes ici
restent expérimentales jusqu'à audit de compatibilité et validation.
