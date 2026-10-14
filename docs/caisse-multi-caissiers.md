# Caisse multi-caissiers

Plusieurs personnes encaissent dans la même boutique. Chaque vente porte le nom de la personne
qui l’a faite, et chaque caissier ne voit que ce dont il a besoin pour vendre.

Décisions du propriétaire :

- **Code PIN personnel.** Chaque caissier a son propre code PIN, que lui seul connaît. Le
  responsable ne le voit jamais. Il peut seulement le réinitialiser.
- **Contrôle des prix.** Le responsable fixe pour chaque caissier une **remise maximale en %**.
  Elle vaut 0 % par défaut : le caissier vend alors au prix affiché.

Migrations (dans l’ordre) :

| Fichier                           | Contenu                                                                                                                                                                                              |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `20261014090000_shop_members.sql` | `shop_members`, `shop_member_invites`, `shop_member_invite_attempts`, `shop_audit_log` ; `shop_role`, `member_shop_ids` ; RPC d’invitation et de gestion de l’équipe.                                |
| `20261014090050_member_pins.sql`  | `member_pins`, `till_sessions` ; `has_shop_permission` ; `set_my_pin`, `verify_my_pin`, `owner_reset_member_pin`, `open_till_session`, `close_till_session`, `my_member_shops`, `list_shop_members`. |
| `20261014090100_member_sales.sql` | `sales.seller_id` (nullable) ; politiques de lecture des membres (`products`, `sales`, `sale_items`, photos) ; `record_sale` et `record_cart_sale` avec `p_till_session`, prix minimal et vendeur.   |

Ces migrations ne détruisent rien. Elles créent des tables, des fonctions et des politiques, et
ajoutent une seule colonne nullable (`sales.seller_id`). Les ventes existantes ne changent pas.
Les politiques propriétaires existantes restent en place.

Deux migrations complémentaires viennent ensuite, dans cet ordre :

- `20261014090200_owner_pin.sql` : code personnel du responsable pour entrer et sortir du
  mode comptoir sur un appareil partagé.
- `20261014090300_cashier_pin_unlock.sql` : preuve de PIN côté serveur, liée au
  `session_id` signé dans le JWT Supabase et valable cinq minutes depuis la dernière vente ou
  vérification. `record_sale` et `record_cart_sale` refusent les appels directs si cette preuve
  manque ou a expiré (`PIN unlock required`). Changer un PIN ou désactiver le caissier révoque
  toutes les anciennes preuves.

La présence d'un PIN dans `member_pins` ne suffit donc **plus** à autoriser une vente.
Le compte Supabase personnel du caissier reste requis.

## Architecture

```
Propriétaire (shops.owner_id)                         Caissier (son propre compte Supabase)
  │ create_member_invite → code XXXX-XXXX-XXXX ──(oral / WhatsApp)──► redeem_member_invite(code)
  │                                                                  │  → shop_members (actif)
  │ set_member_permissions / set_member_active                       │ set_my_pin (4-6 chiffres)
  │ owner_reset_member_pin                                           ▼
  │                                                  (a) appareil personnel :
  │                                                      verify_my_pin à l'ouverture et après
  │                                                      5 min d'inactivité, puis
  │                                                      record_sale / record_cart_sale
  │                                                      → seller_id = le caissier
  ▼
(b) appareil partagé connecté au compte du PROPRIÉTAIRE :
    « Caissier : … · Changer » → le caissier tape SON PIN → open_till_session → jeton
    record_sale / record_cart_sale(…, p_till_session => jeton) → seller_id = le caissier,
    remise maximale du caissier ; close_till_session au changement ou à la déconnexion.
```

- **Propriétaire** : `shops.owner_id`, sans changement. Le propriétaire n’est jamais membre de sa
  propre boutique (un trigger le refuse).
- **Caissier** : une ligne de `shop_members` (`role = 'cashier'`, seul rôle en V1), avec
  `active`, `can_view_shop_sales` (faux par défaut), `max_discount_pct` (0 à 100, 0 par défaut)
  et `display_name`.
- **Aucune écriture directe par un membre.** Les membres n’ont que des politiques `SELECT`, et
  aucune politique `FOR ALL`. Toutes les écritures passent par des fonctions
  `SECURITY DEFINER`. Ces fonctions ont un `search_path` vide, qualifient tous les objets et
  vérifient `auth.uid()` puis le rôle avant toute lecture.
- **Journal** : `shop_audit_log` enregistre l’invitation (créée, annulée), le membre (arrivé,
  désactivé, réactivé), les permissions, le PIN (choisi, changé, réinitialisé), l’échec d’un PIN de
  session de caisse et la session de caisse (ouverte, fermée). Seul le propriétaire le lit. Le
  journal ne contient jamais de PIN, d’empreinte, de jeton ni de code d’invitation.

Front :

| Fichier                                             | Rôle                                                                                                                                                                                    |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/features/auth/AuthGate.tsx`                    | Charge la boutique possédée (`owner_id = moi`) et `my_member_shops()`. Caissier seul : espace caissier. Les deux : choix. Aucun : création de boutique ou « J’ai un code de caissier ». |
| `src/features/team/CashierApp.tsx`                  | Espace caissier : Vendre et « Mes ventes » seulement, verrou PIN à l’ouverture et après 5 minutes sans activité, « Choisissez votre code PIN ».                                         |
| `src/features/team/PinPad.tsx`, `PinScreens.tsx`    | Pavé numérique masqué (touches de 64 px), écran de verrouillage, choix ou changement du PIN.                                                                                            |
| `src/features/team/TillSwitch.tsx`                  | Vendre (propriétaire) : « Caissier : … · Changer ».                                                                                                                                     |
| `src/features/team/TeamPanel.tsx`                   | Ma boutique → Équipe : invitation, remise maximale, « voit toutes les ventes », désactivation, réinitialisation du PIN, annulation d’invitation.                                        |
| `src/features/team/JoinPage.tsx`                    | Saisie du code d’invitation.                                                                                                                                                            |
| `src/features/history/HistoryPage.tsx`              | « Ventes par caissier » (résumé et filtre) pour le propriétaire, « Mes ventes » pour le caissier.                                                                                       |
| `src/lib/team.ts`, `teamRules.ts`, `tillSession.ts` | Appels RPC, règles partagées avec SQL (prix minimal, PIN trivial), messages, jeton de session de caisse (mémoire + `sessionStorage`, jamais `localStorage`).                            |

## Matrice des permissions

« Membre » désigne un caissier **actif**. Un membre désactivé n’a plus aucun droit : il est
traité comme un inconnu.

| Donnée / action                                        | Propriétaire                | Membre avec PIN                               | Membre sans PIN      | Autre utilisateur | `anon`  |
| ------------------------------------------------------ | --------------------------- | --------------------------------------------- | -------------------- | ----------------- | ------- |
| `shops` (table : GPS, `owner_id`)                      | lecture/écriture (inchangé) | non (nom et ville via `my_member_shops`)      | idem                 | non               | non     |
| `products` + photos                                    | tout (inchangé)             | lecture seule                                 | lecture seule        | non               | non     |
| `arrivals` (coûts), `shop_expenses`                    | tout (inchangé)             | non                                           | non                  | non               | non     |
| Agrégats (`shop_dashboard`…)                           | oui                         | non (`Shop not found`)                        | non                  | non               | non     |
| `sales` / `sale_items`                                 | toutes                      | les siennes ; toutes si `can_view_shop_sales` | idem                 | non               | non     |
| Vendre (`record_sale`, `record_cart_sale`)             | oui, sans minimum           | oui, prix ≥ minimum                           | non (`PIN required`) | non               | non     |
| `p_till_session` (vendre au nom d’un caissier)         | oui (jeton valide)          | non (`Till session invalid`)                  | non                  | non               | non     |
| `shop_members`, invitations, journal                   | lecture (RPC / RLS)         | non                                           | non                  | non               | non     |
| `member_pins`, `till_sessions`, tentatives             | non (RPC seulement)         | non                                           | non                  | non               | non     |
| Inviter, permissions, désactiver, réinitialiser un PIN | oui                         | non                                           | non                  | non               | non     |
| `set_my_pin`, `verify_my_pin`                          | —                           | oui (son PIN)                                 | oui (premier PIN)    | non               | non     |
| `open_till_session`, `close_till_session`              | oui                         | non                                           | non                  | non               | non     |
| Écriture directe dans une table                        | inchangé                    | **refusée partout**                           | refusée              | refusée           | refusée |

Privilèges : sur les nouvelles tables, `anon` et `authenticated` n’ont aucun `INSERT`, `UPDATE`,
`DELETE`, `TRUNCATE`, `TRIGGER` ni `REFERENCES`. `authenticated` ne garde que `SELECT` sur
`shop_members` et `shop_audit_log`, filtré par la RLS. Seul le propriétaire passe ce filtre. Toutes
les fonctions de `public` sont fermées à `anon`. Les fonctions internes (`member_pin_check`,
`sale_seller`, `till_session_member`, `assert_*`, `shop_audit`…) ne sont pas exécutables par les
rôles d’API.

`has_shop_permission(shop, permission)` et `shop_role(shop)` sont des fonctions
`SECURITY DEFINER STABLE`, avec un `search_path` vide. Elles ne renseignent que sur l’appelant.
Permissions : `manage`, `sell`, `view_products`, `view_own_sales`, `view_shop_sales`.

## Code PIN : conception et modèle de menace

**Stockage.** `member_pins.pin_hash` est un hash bcrypt :
`extensions.crypt(pin, extensions.gen_salt('bf', 10))`. Chaque PIN a son propre sel et un coût
de 10. Le PIN n’est jamais stocké en clair. Aucune fonction ne le renvoie et aucune ne l’écrit
dans le journal. La table n’a aucune politique RLS et aucun privilège : même le propriétaire ne
peut pas la lire.

**Format.** 4 à 6 chiffres. Les codes triviaux sont refusés, côté serveur
(`member_pin_assert_strength`) comme dans l’écran :

- tous les chiffres identiques ;
- les suites croissantes ou décroissantes ;
- les motifs répétés (1212, 121212, 123123) ;
- quelques codes très courants.

**Verrouillage.** Un seul compteur par membre est partagé par `verify_my_pin`,
`open_till_session` et la vérification de l’ancien PIN dans `set_my_pin`. Au 5e échec, le PIN est
bloqué 15 minutes (`locked_until`), même si le bon code est ensuite tapé. Après ce délai, le
compteur repart de zéro. Un bon PIN remet aussi le compteur à zéro. Un échec ne lève pas
d’exception, sinon l’incrément serait annulé : la fonction renvoie un statut.

**Réinitialisation.** `owner_reset_member_pin` efface le hash et impose un changement
(`must_change`). Elle ferme aussi les sessions de caisse ouvertes du membre. Le caissier choisit
son nouveau code à sa prochaine ouverture. Le propriétaire ne l’apprend jamais. Sans PIN, le
membre ne peut ni vendre ni être choisi sur l’appareil partagé.

**Jeton de session de caisse.** Le jeton fait 256 bits (`gen_random_bytes(32)` en hexadécimal) et
n’est renvoyé qu’une fois. La base ne garde que son empreinte SHA-256. Il est lié à la boutique et
au membre, et expire après 12 h ou à `close_till_session`. Il devient invalide si :

- le membre est désactivé ;
- le PIN du membre est réinitialisé ;
- quelqu’un d’autre que le propriétaire l’utilise ;
- il est présenté dans une autre boutique.

Côté front, le jeton vit en mémoire et dans `sessionStorage`, jamais dans `localStorage`. Il est
effacé :

- au changement de caissier ;
- au retour en « Vous (responsable) » ;
- à la déconnexion (`SIGNED_OUT`) ;
- quand il expire.

**Code d’invitation.** 12 caractères pris dans un alphabet de 30 symboles sans 0/O, 1/I/L ni U
(environ 59 bits). Le tirage est cryptographique, par rejet, sans biais. La base ne stocke que
l’empreinte SHA-256. Le code est valable 48 h, une seule fois, et le propriétaire peut l’annuler.
5 codes faux en 15 minutes bloquent l’utilisateur 15 minutes. Un code refusé ne dit jamais
pourquoi.

Menaces couvertes :

| Menace                                                          | Parade                                                                                                                                                     |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Le caissier s’accorde une remise ou vend à 0 FCFA               | Prix minimal vérifié **en base**, ligne par ligne : `round(prix affiché × (1 − remise max / 100))`. L’écran le vérifie aussi, mais seule la base fait foi. |
| Le caissier lit les coûts, marges, charges, GPS, liste d’équipe | Pas de lecture de `arrivals`, `shop_expenses`, `shops`, `shop_members` ni des agrégats. `products` n’a pas de colonne de coût (vérifié par test).          |
| Le caissier modifie le stock ou efface des ventes               | Aucune politique d’écriture pour les membres. `quantity_on_hand` et `status` ne changent que par les RPC de vente.                                         |
| Un collègue utilise le téléphone resté ouvert                   | Verrou par PIN après 5 minutes sans activité, et bouton « Verrouiller ».                                                                                   |
| Force brute du PIN ou du code d’invitation                      | 5 essais par 15 minutes. bcrypt pour le PIN. 59 bits pour le code.                                                                                         |
| Fuite de la base (sauvegarde, accès service)                    | Le PIN est haché en bcrypt. Les jetons et les codes ne sont gardés que sous forme d’empreinte.                                                             |
| Caissier renvoyé                                                | `set_member_active(false)` coupe tout de suite la lecture, la vente et les sessions de caisse. L’historique est conservé.                                  |
| Jeton volé sur l’appareil partagé                               | Utilisable seulement avec la session Supabase du propriétaire, dans la même boutique, pendant 12 h au plus. Il est fermé au changement de caissier.        |

Limites connues :

- **Appareil partagé = compte du propriétaire ouvert.** Le code du responsable protège
  désormais le retour aux écrans de gestion dans l'interface. **Mais le JWT Supabase présent
  dans le navigateur reste celui du propriétaire : un utilisateur technique disposant de
  cet appareil peut appeler les fonctions administrateur directement.** Ce n'est donc pas
  une isolation des droits côté serveur. Pour un caissier non administrateur, utilisez
  impérativement son compte Supabase individuel (cas a).
- Un PIN de 4 à 6 chiffres reste un **second facteur local**. Le premier facteur est le compte
  Supabase (e-mail et mot de passe) du caissier. Vérifiez la disponibilité de la protection
  contre les mots de passe compromis dans Supabase Auth, sans souscrire d'option payante.
- Les PIN passent en argument des RPC (HTTPS). Ne journalisez pas le corps des requêtes
  PostgREST. Gardez `log_statement` à `none` ou `ddl` (valeurs par défaut de Supabase).

## Contrats des RPC

Toutes ces RPC sont exécutables par `authenticated` seulement. Les erreurs ont un **message
anglais stable**, le SQLSTATE est entre parenthèses.

| RPC                                                                                                      | Appelant                  | Retour / erreurs                                                                                                                                                                                                                                    |
| -------------------------------------------------------------------------------------------------------- | ------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `create_member_invite(p_shop_id, p_display_name, p_can_view_shop_sales = false, p_max_discount_pct = 0)` | propriétaire              | `{invite_id, code "XXXX-XXXX-XXXX", display_name, expires_at, can_view_shop_sales, max_discount_pct}`. Le code n’est renvoyé qu’ici. `Shop not found` (42501), `Invalid display name`, `Invalid discount`, `Too many pending invites` (20 au plus). |
| `list_member_invites(p_shop_id)`                                                                         | propriétaire              | Invitations encore utilisables, sans l’empreinte.                                                                                                                                                                                                   |
| `revoke_member_invite(p_invite_id)`                                                                      | propriétaire              | `true`. `Invite not found` (42501), `Invite already used`.                                                                                                                                                                                          |
| `redeem_member_invite(p_code)`                                                                           | tout utilisateur connecté | `{status: 'joined', member_id, shop_id, shop_name, display_name}`, `{status: 'invalid'}` ou `{status: 'locked', retry_after}`. `Owner cannot join own shop`. Majuscules, espaces et tirets sont ignorés.                                            |
| `my_member_shops()`                                                                                      | tout utilisateur connecté | Ses adhésions **actives** : `member_id, shop_id, shop_name, shop_city, shop_country, shop_currency, display_name, role, can_view_shop_sales, max_discount_pct, pin_set, pin_must_change`.                                                           |
| `list_shop_members(p_shop_id)`                                                                           | propriétaire              | Équipe avec `pin_set`, `pin_must_change`, `pin_locked_until`, jamais le PIN.                                                                                                                                                                        |
| `set_member_active(p_member_id, p_active)`                                                               | propriétaire              | `{id, active, deactivated_at}`. `Member not found` (42501).                                                                                                                                                                                         |
| `set_member_permissions(p_member_id, p_can_view_shop_sales, p_max_discount_pct)`                         | propriétaire              | `{id, can_view_shop_sales, max_discount_pct}`. `Invalid discount`, `Member not found`.                                                                                                                                                              |
| `owner_reset_member_pin(p_member_id)`                                                                    | propriétaire              | `{id, pin_set: false, pin_must_change: true}`. `Member not found`.                                                                                                                                                                                  |
| `set_my_pin(p_shop_id, p_new_pin, p_current_pin = null)`                                                 | membre actif              | `{status: 'ok'}`, `{status: 'invalid', attempts_left}` ou `{status: 'locked', retry_after}`. `Invalid PIN format`, `PIN too simple` (22023), `Shop not found`. L’ancien PIN est exigé s’il en existe un.                                            |
| `verify_my_pin(p_shop_id, p_pin)`                                                                        | membre actif              | `{status: 'ok' \| 'invalid' \| 'locked' \| 'not_set', …}`. `Shop not found`.                                                                                                                                                                        |
| `open_till_session(p_shop_id, p_member_id, p_pin)`                                                       | propriétaire              | `{status: 'ok', token, session_id, expires_at, member_id, display_name, max_discount_pct}` ou un statut d’échec comme `verify_my_pin`. `Member not found` (membre inactif ou d’une autre boutique).                                                 |
| `close_till_session(p_shop_id, p_token)`                                                                 | propriétaire              | `true` si une session ouverte a été fermée, sinon `false` (idempotent).                                                                                                                                                                             |
| `record_sale(…, p_client_operation_id, p_till_session = null)`                                           | propriétaire, membre      | id de la vente. Voir ci-dessous.                                                                                                                                                                                                                    |
| `record_cart_sale(…, p_client_operation_id, p_till_session = null)`                                      | propriétaire, membre      | id de la vente. Contrat complet : [`contrat-panier.md`](contrat-panier.md).                                                                                                                                                                         |

`record_sale` et `record_cart_sale` :

1. Session, puis propriétaire ou membre actif. Sinon : `Authentication required` ou
   `Shop not found`.
2. Contrôles existants des paramètres et du panier.
3. Idempotence par la même clé et le même verrou consultatif qu’avant. Un rejeu renvoie la vente
   déjà enregistrée, même si la session de caisse a été fermée entre-temps.
4. Vendeur :
   - avec `p_till_session` : propriétaire seulement, jeton valide, sinon `Till session invalid` ;
   - sans jeton : le propriétaire vend sans minimum ; un membre doit avoir un PIN, sinon
     `PIN required`.
5. Pour chaque ligne : disponibilité, pièce unique, stock, puis **prix minimal** si le vendeur
   est un membre. En dessous : `Price below allowed minimum` (P0001), avec
   `DETAIL item N: product_id …, minimum_price=9000`.
6. Écriture avec `seller_id`. Le stock reste ≥ 0 et une pièce unique passe en `sold`. `is_test`
   est inchangé.

Les anciennes signatures sans `p_till_session` sont supprimées puis recréées avec ce paramètre
en plus. Une seule surcharge existe, donc un appel PostgREST sans `p_till_session` n’est pas
ambigu (pas de PGRST203). Le front actuel continue de marcher sans changement.

## Messages d’erreur (front)

| Serveur                                 | Écran                                                                                                                  |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `Price below allowed minimum`           | « Ce prix est en dessous du minimum autorisé (9 000 FCFA). Demandez au responsable. »                                  |
| statut `locked` (PIN ou invitation)     | « Trop d’essais. Réessayez dans 15 minutes. »                                                                          |
| statut `invalid` (PIN)                  | « Code PIN incorrect. Encore N essais. » / « … Dernier essai avant le blocage. »                                       |
| statut `not_set` (session de caisse)    | « Ce caissier n’a pas encore choisi son code PIN. Il doit l’ouvrir sur son téléphone. »                                |
| `PIN required`                          | « Choisissez d’abord votre code PIN pour pouvoir vendre. »                                                             |
| `Till session invalid`                  | « La caisse de ce caissier est fermée ou a expiré. Touchez « Changer » et entrez à nouveau son code PIN. »             |
| `Shop not found` (vente)                | « Vous n’avez plus accès à cette boutique. Demandez au responsable. »                                                  |
| `PIN too simple` / `Invalid PIN format` | « Ce code est trop facile à deviner. Choisissez-en un autre. » / « Le code PIN compte 4 à 6 chiffres. »                |
| invitation `invalid`                    | « Ce code ne marche pas : il est faux, déjà utilisé, annulé ou trop ancien. Demandez un nouveau code au responsable. » |
| `Owner cannot join own shop`            | « Ce code est pour un caissier : vous êtes déjà le responsable de cette boutique. »                                    |

## Hors connexion

En cas de vente d'un caissier sur son propre compte, si le serveur renvoie
`PIN unlock required` à la synchronisation, la vente reste dans la file. L'ouverture
correcte du PIN relance l'envoi ; aucune vente en attente n'est supprimée à cause de
l'expiration du code.

- **Cas (a), caissier sur son compte.** La file hors connexion actuelle (`src/lib/offline.ts`)
  marche telle quelle. Elle rejoue avec le compte du caissier, donc `seller_id` est le bon.
  L’écran applique le prix minimal avant de mettre la vente en file. Une vente en file peut quand
  même être refusée au rejeu : remise baissée ou caissier désactivé entre-temps. Elle apparaît
  alors dans les ventes refusées, avec la raison.
- **Cas (b), session de caisse.** Les ventes passent **en ligne seulement**
  (`recordTillSale`). La file actuelle ne garde pas le jeton : une vente rejouée plus tard serait
  attribuée au propriétaire. Hors réseau, l’écran le dit et n’enregistre rien. **Changement
  demandé à la personne qui maintient `offline.ts`** (ce fichier n’a pas été modifié ici) :
  1. ajouter `tillSession?: string` et `sellerName?: string` à `PendingSale` ;
  2. accepter un `tillSession` facultatif dans `resilientSale` et `queueSale` ;
  3. transmettre `p_till_session` dans `syncPendingSales` via `recordSale` (paramètre facultatif
     en plus) ;
  4. classer `Till session invalid` comme rejet définitif, avec le message de `saleErrors`.

  Le jeton expire après 12 h, donc une vente gardée plus longtemps serait refusée. Prévoir alors
  « rattacher au responsable » ou « rouvrir la caisse du caissier ».

## Déploiement

Production : projet `bmbwmwgfzrijglzcgjut`. **Rien n’a été appliqué** par ce travail.

1. **Ordre des migrations.** Les anciennes migrations de #6 et #11 ont déjà été
   renumérotées en `20261013...`. Les tests SQL vérifient que les vingt migrations de
   production forment le préfixe exact de l'historique et que la caisse arrive après.
   Tester **toutes** les migrations de cette PR dans un PostgreSQL jetable avec
   `tests/sql/run.sh --tmp-cluster`. Ne pas employer ce script sur une base réelle.
   Les migrations de production ne doivent être appliquées qu'après revue des droits d'accès,
   des commandes DDL et des procédures de repli.
2. **pgcrypto.** Vérifiez qu’il est dans le schéma `extensions`, ce qui est la norme Supabase :
   `select extnamespace::regnamespace from pg_extension where extname = 'pgcrypto'`. La migration
   `20261014090050` l’installe là s’il est absent. S’il est ailleurs, elle échoue avant toute
   écriture.
3. Appliquez les migrations dans l’ordre des noms. Chaque fichier est une transaction.
4. Déployez le front. L’ancien front reste compatible avec la nouvelle base. Le nouveau front
   reste compatible avec l’ancienne base pour le propriétaire seul : si `my_member_shops`
   manque, il ouvre l’espace propriétaire.
5. Vérifiez les conseillers Supabase (sécurité et performance) sur la branche puis en production.
6. Dans Supabase Auth, activez la **protection contre les mots de passe compromis**
   (HaveIBeenPwned).
7. Faites un essai réel avec un compte caissier de test (données `is_test`) : invitation, PIN,
   vente au minimum, vente refusée sous le minimum, désactivation.

## Compatibilité avec la production actuelle

Les migrations sont appliquées **avant** le nouveau front. `tests/sql/production_compat.sql`
rejoue, en propriétaire authentifié et après toutes les migrations, chaque appel Supabase du
front de `main` (création de boutique avec quartier et GPS, produits, arrivages, charges,
réglages de la boutique, photos, `record_sale` sans `p_till_session`). Il passe : le front
actuellement en ligne continue de fonctionner sur la base migrée.

## Retour arrière

- **Front seul.** Redéployez la version précédente. La base reste compatible : l’ancien front
  appelle `record_sale` sans `p_till_session` et vend au nom du propriétaire.
- **Base, arrêt immédiat sans perte.** Désactivez les caissiers (`set_member_active(false)`).
- **Base, retour complet.** Trois scripts testés (`tests/sql/rollback.sql`), à exécuter dans
  l’ordre, chacun en une transaction avec le rôle postgres, puis `notify pgrst, 'reload schema'` :
  1. `supabase/rollback/1_caisse_20261014.sql` : annule 20261014090000 à 20261014090300
     (équipe, invitations, PIN, sessions de caisse, code du responsable, déverrouillages PIN,
     journal) et remet `record_sale` / `record_cart_sale` en version propriétaire seul ;
  2. `supabase/rollback/2_agregats_panier_20261013.sql` : annule 20261013100100 et 20261013100200 ;
  3. `supabase/rollback/3_ecritures_sensibles_20261013.sql` : annule 20261013100000.

  Les boutiques, produits, ventes, arrivages et charges ne sont jamais touchés.
  `sales.seller_id` reste (nullable, ignorée par l’ancien front). Exportez `shop_audit_log` et
  la liste de l’équipe avant le script 1.

## État réel et limites avant publication

- **Terminé dans cette branche :** interface multi-caissiers, invitations, PIN des caissiers,
  code du responsable, panier multi-articles avec vente atomique, suivi des vendeurs,
  prix minimal imposé par le serveur, et vérification PIN en base par session JWT.
- **Hors connexion, compte caissier individuel :** les ventes à une ligne restent en attente
  et **ne sont pas rejetées** lorsque le déverrouillage du PIN a expiré. Après la saisie
  correcte du PIN, `retrySyncAfterPinUnlock` relance leur synchronisation avec leur UUID initial.
- **Hors connexion, panier multi-articles :** conservé à l'écran si le réseau manque. Après une
  réponse réseau incertaine, la session du navigateur conserve le même UUID pour un nouvel essai.
  Il n'existe pas encore de file persistante IndexedDB pour les paniers complets.
- **Appareil partagé du propriétaire : limite de sécurité importante.** Le PIN du responsable
  verrouille les écrans de l'application mais ne change pas les privilèges du JWT du propriétaire
  dans le navigateur. Ce dispositif n'offre pas la même isolation qu'un caissier connecté sur
  **son propre compte Supabase**. Ne pas confier une session propriétaire à un employé non fiable.
- **À isoler du chantier de caisse :** passerelle QR publique et demandes clients issues de
  WhatsApp, Instagram ou TikTok ; écran détaillé des mouvements de stock ; éventuel journal
  d'équipe visible dans l'application.
- **Supabase Auth :** le conseiller de sécurité signale une protection contre les mots de passe
  compromis désactivée. La disponibilité de ce réglage dépend de l'offre Supabase ;
  **ne pas engager de frais ni modifier l'abonnement sans autorisation**.
- **Production :** les migrations multi-caissiers n'ont pas été appliquées. Cette PR reste en
  brouillon et ne doit pas être fusionnée tant que le mode appareil partagé n'est pas clarifié et
  qu'un essai fonctionnel isolé de bout en bout n'est pas validé.

## Tests

- SQL : `tests/sql/members.sql` (plus de 150 vérifications) et `tests/sql/members_concurrency.sh`,
  lancés par `tests/sql/run.sh --tmp-cluster` avec les tests existants.
- Vitest : `src/lib/teamRules.test.ts`, `src/lib/tillSession.test.ts`,
  `src/features/auth/AuthGate.test.tsx`, `src/features/team/*.test.tsx`,
  `src/features/sale/SaleForm.test.tsx`, `src/features/sale/saleErrors.test.ts`,
  `src/features/history/sellerTotals.test.ts`.
