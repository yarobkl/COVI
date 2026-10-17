# COVI — Passerelle QR et réseaux sociaux : protocole de validation en environnement isolé

**État : code et tests sur branche uniquement. NON déployé. Ne pas appliquer à la production.**

## Architecture V1

1. La page cliente `#/commander/<token>?via=qr|social` interroge
   `/functions/v1/public-checkout?token=<token>` depuis le domaine autorisé.
2. La fonction Edge renvoie uniquement le nom de la boutique et les catégories
   disponibles. Ni quantité exacte, ni coût d'achat, ni données privées.
3. Le formulaire demande une vérification Cloudflare Turnstile configurée
   pour l'action `covi_checkout`, avec un hostname identique à celui du site.
4. À l'envoi, la fonction Edge vérifie le format JSON, les UUID, les quantités,
   les prix, le plafond total, les champs de livraison et le contrôle anti-robot.
   Elle appelle ensuite exclusivement la RPC de **création de demande**.
5. La fonction utilise une clé Supabase secrète côté serveur uniquement ;
   les RPC publiques sont **inaccessibles** directement aux rôles
   `anon` et `authenticated`. Aucun endpoint public ne peut approuver,
   confirmer un paiement ou modifier les stocks.
6. Les quotas PostgreSQL sont atomiques entre instances Edge. Les limites
   sont fixées dans le brouillon SQL, jamais choisies par le visiteur :
   catalogue par source 30/min et par lien 120/min ;
   demande par source 5/min et 80/jour ;
   demande par lien 60/min après challenge anti-robot valide.
   Le plafond historique de soumissions 60/min et 1 000/jour par boutique
   reste dans la RPC de création.
7. Les identifiants de source et de lien sont des empreintes HMAC SHA-256
   générées avec un secret serveur ; aucun IP ou token brut n'est écrit
   dans la nouvelle table des quotas. Les en-têtes de proxy pouvant être
   falsifiables, l'identification par IP **n'est pas** une frontière de sécurité
   suffisante : challenge obligatoire, plafonds par lien, RLS et permissions
   restent indispensables.

## Configuration exigée pour un test isolé

Utiliser une **autre instance Supabase**, une autre URL de site et un domaine
Turnstile autorisé, sans copier de vrais clients. Les variables du serveur
Edge sont :

- `COVI_GATEWAY_ENABLED=true` uniquement sur le bac à sable
- `COVI_PUBLIC_ORIGIN=https://<domaine-de-test>` (origine exacte)
- `COVI_SUPABASE_SECRET_KEY=<clé secrète de la base isolée>`
- `COVI_GATEWAY_PEPPER=<secret aléatoire d'au moins 32 caractères>`
- `COVI_TURNSTILE_SECRET=<clé secrète Turnstile du site de test>`
- `SUPABASE_URL` fournie par Supabase pour la base isolée

Dans la compilation web **de test uniquement** :

- `VITE_COVI_CATEGORY_CHECKOUT_ENABLED=true`
- `VITE_COVI_TURNSTILE_SITE_KEY=<clé publique Turnstile du test>`
- `VITE_SUPABASE_URL=<URL de l'instance Supabase isolée>`

La clé secrète, la clé de service, le sel HMAC et la clé privée Turnstile
ne doivent **jamais** être nommés `VITE_*`, être enregistrés dans Git,
ou être affichés dans une page web.

La fonction `supabase/functions/public-checkout/index.ts` utilise
`supabase/config.toml` avec `verify_jwt = false` uniquement pour
cette fonction **parce que les visiteurs ne sont pas connectés**.
La vérification anti-robot reste obligatoire au niveau du code.
Le bouton public n'est jamais une confirmation de paiement.

## Liste d'essais obligatoires avant toute autorisation

- Accès direct aux RPC depuis un navigateur anonyme : permission refusée.
- Origine non autorisée, JSON trop volumineux ou non valide, identifiants
  faux, quantité excessive, prix négatif, livraison sans téléphone : refus.
- Captcha absent, expiré, faux ou utilisé pour un autre hostname/action :
  refus et aucune commande créée.
- Dépôt QR et réseau social avec demandes normales : visible uniquement
  dans la boîte du commerçant authentifié, sans perte de l'identifiant
  d'opération lors de la reprise réseau.
- Inondation multi-instance : quotas source et lien atomiques,
  une commande en double ne doit jamais générer deux ventes.
- Approbation et encaissement par un visiteur : toujours refusés ;
  seules les confirmations manuelles du vendeur déclenchent la sortie
  de stock.
- Vérification réelle des permissions JWT, `auth.uid()`, PostgREST,
  RLS, rôle serveur, verrouillage transactionnel et séparation des boutiques.
- Tests de conformité sur iPhone, Android, bureau et lien partagé via
  WhatsApp, Facebook, Instagram et TikTok.

## Conditions préalables et exploitation

Les essais automatisés GitHub vérifient le code et une fixture PostgreSQL
jetable, **pas** les véritables règles Supabase/Auth en staging.
Il faut créer un environnement isolé avant de pouvoir valider le bout
en bout. Les options sont désactivées par défaut.

Plan de coupure : désactiver `COVI_GATEWAY_ENABLED` et/ou le flag web ;
l'ancienne caisse continue à fonctionner. La rotation du lien de boutique
invalide les QR imprimés : avertir les commerçants avant toute rotation.

Prévoir une purge régulière des anciennes fenêtres de quota et une politique
de conservation des téléphones/notes clients. Ces décisions et les tests de
charge/anti-abus réels restent des **conditions bloquantes avant production**.

Aucune migration de production, configuration de secret, déploiement Edge
ni modification d'authentification n'a été effectuée dans ce chantier.
