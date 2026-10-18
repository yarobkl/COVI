# COVI — Inscription propriétaire, secteur et confirmation e-mail

## Parcours de création de compte

1. Sur le site COVI, « Créer un compte » ouvre un vrai formulaire propriétaire : prénom, nom, téléphone international, nom de l'établissement, adresse e-mail, mot de passe et confirmation, puis secteur `retail` (boutique de vêtements), `restaurant` ou `salon` (coiffure).
2. `supabase.auth.signUp` enregistre les informations **de présentation** dans `user_metadata`, avec `emailRedirectTo: window.location.origin`. Le profil métier **ne donne aucun accès** à une boutique et ne doit jamais autoriser des requêtes SQL.
3. Avec **Confirm Email activé dans Supabase**, la session est absente : le propriétaire doit ouvrir le lien contenu dans le courriel de confirmation. Une fois la session établie, il complète ville, quartier et éventuellement GPS. La création de l'établissement reste une opération serveur autorisée par `auth.uid()`.
4. Le choix du secteur et le nom déjà donnés sont préremplis dans la deuxième étape. Il est possible de les ajuster avant la création définitive.
5. Les utilisateurs existants gardent leur connexion habituelle ; les profils de comptes Google/Facebook ou anciens complètent leur numéro de téléphone manquant avant de créer un établissement.
6. Les salariés rejoignant un espace avec un code ne doivent pas être forcés à créer un établissement.

## Configuration obligatoire avant la production

**Ce code est en développement sur `feature/covi-inscription-pme-secteurs-20261018`. Aucune configuration Supabase de production n'est modifiée par cette branche.**

- Supabase Dashboard → Authentication → Providers → Email : vérifier que l'inscription par e-mail est autorisée et **activer « Confirm Email »**. Ce paramètre est indispensable. Si désactivé, Supabase peut connecter immédiatement un nouvel inscrit ; le site ne peut pas garantir un lien de confirmation obligatoire.
- Supabase Dashboard → Authentication → URL Configuration : Site URL `https://covi-snowy.vercel.app` et destinations HTTPS de préproduction explicitement autorisées. Ne pas ajouter de redirection HTTP non fiable.
- Supabase Dashboard → Authentication → Email Templates → Confirm signup : conserver un lien effectif vers `{{ .ConfirmationURL }}` ; personnaliser « Confirmez votre compte COVI ». Tester expiration du lien, répétition de l'inscription, message anti-énumération et reprise sur iPhone/Android.
- Configurer l'envoi SMTP transactionnel avec un domaine vérifié et vérifier réception, SPF/DKIM/DMARC, quotas et erreurs. L'e-mail Auth de vérification est géré par Supabase, et non par la fonction Edge de bienvenue.
- Google et Facebook : le premier compte obtenu via OAuth peut recevoir automatiquement **un e-mail de bienvenue** (pas un faux lien de revalidation) depuis la fonction Edge `covi-welcome` après la session authentifiée.
- Pour déployer `covi-welcome`, fournir comme secrets serveur `RESEND_API_KEY` et `COVI_WELCOME_FROM` (domaine vérifié), ainsi que les variables Supabase serveur gérées par la plateforme. Ne jamais exposer la clé Resend ni `SUPABASE_SERVICE_ROLE_KEY` dans Vite/`VITE_*`.
- La fonction vérifie le JWT auprès de Supabase Auth, l'e-mail confirmé, le fournisseur Google/Facebook, la fenêtre de création de compte de 24 heures et le marqueur serveur `covi_welcome_email_sent_at`. Elle utilise le header Resend `Idempotency-Key: covi-welcome/<user id>` pour rendre les tentatives répétées sûres. Si l'envoi échoue, l'ouverture du compte **ne doit pas être bloquée**.
- Tester réellement un **nouvel utilisateur** de chacun des trois secteurs, puis un nouvel utilisateur Google et Facebook, plus un compte préexistant (aucun nouveau courriel de création).
- Vérifier sur un dispositif et une boîte e-mail réels : confirmation reçue, clic de lien, association au bon compte, création d'établissement et bonne activité, arrivée unique du message de bienvenue. Ne pas promettre la délivrabilité tant que le SMTP ou Resend n'est pas configuré.
- Avant activation du Restaurant et Salon : appliquer en préproduction les migrations de la PR #44 et tester les politiques RLS. Ne pas connecter le nouveau formulaire métier à une production sans schéma `business_kind` et `create_my_business_with_location`.

## Données et limites

- Les informations utilisateur envoyées à Auth sont des indications de parcours ; le serveur valide `auth.uid()`, secteur, devise `XAF` et isolation par `shop_id` lors de la création.
- Un nouveau compte n'est pas un établissement. Le nom et le secteur sont conservés jusqu'au deuxième écran puis validés par le RPC `create_my_business_with_location`.
- L'état « e-mail envoyé » de Supabase ne prouve pas que le message a été distribué dans la boîte du destinataire.
- La fonction de bienvenue dépend d'un service d'envoi externe configuré et d'un domaine expéditeur vérifié, et n'est **pas** active en production tant que ce déploiement n'est pas validé.

## Localisation CEMAC — exigence d'adresse pour chaque nouvel établissement

La version cible suit le chemin **pays → ville → arrondissement/commune → quartier → adresse physique**. La liste de pays de la **création d'établissement** est limitée aux six États membres CEMAC, avec le Congo en premier ; les comptes/établissements historiques hors zone restent inchangés.

- Pays : République du Congo, Cameroun, Gabon, République centrafricaine, Guinée équatoriale, Tchad ([CEMAC](https://cemac.int/about/)).
- Brazzaville : les neuf arrondissements de la commune ([Ministère du développement durable du Congo](https://www.developpement-durable.gouv.cg/2017/06/05/brazzaville-brazza-la-verte/)).
- Pointe-Noire : six arrondissements ([Les Dépêches de Brazzaville](https://www.adiac-congo.com/node/137583)).
- Yaoundé : sept communes d'arrondissement ([Communauté urbaine de Yaoundé](https://yaounde.cm/communes-darrondissement/)).
- Douala : six arrondissements (nomenclature nationale du Cameroun, [INS](https://stat.cm/nada/index.php/catalog/114/download/973)).
- Les communes, arrondissements et quartiers **non vérifiés** ne sont pas inventés : « Autre arrondissement / commune » puis « Autre quartier » permettent la saisie libre.
- Quartiers proposés dans les zones sélectionnées : répertoire conservateur, en cours d'extension. Ils sont filtrés par arrondissement ; aucun quartier d'une autre zone n'est mélangé par défaut.
- Adresse physique descriptive **obligatoire** : 10–240 caractères, au moins deux mots avec lettres, sur l'écran de création et dans la fonction serveur **nouvelle** `create_my_business_with_address`. Numéro de rue non obligatoire (absence d'adressage normalisé dans certaines zones) ; avenue, lieu-dit et repère précis acceptés. La saisie n'équivaut **pas** à une vérification externe de réalité.
- GPS uniquement facultatif et déclenché par le propriétaire. L'adresse saisie est conservée, GPS ne la remplace pas.
- La migration `20261018010000_covi_business_address_cemac.sql` ajoute `shops.administrative_area`, `shops.address_line` sans modifier les adresses historiques. L'ancienne RPC est conservée pour les versions mobiles existantes ; un durcissement global des nouveaux INSERT devra être prévu après migration de tous les clients historiques.
- Ne pas appliquer sur Supabase de production ni fusionner PR #44/#50 avant une recette complète. Le backend multisectoriel et le nouveau formulaire doivent être activés ensemble, sinon un RPC peut manquer.

### Recette préalable à la publication

1. Créer un compte pour chaque secteur, confirmer son e-mail, vérifier que l'activité et le nom préremplis persistent.
2. Brazzaville : Moungali → Moukondo → adresse physique descriptive → création autorisée. Test négatif adresse vide, arrondissement absent, ville seule.
3. Pointe-Noire : contrôle 6 arrondissements. Yaoundé/Douala : contrôler les 7/6 divisions.
4. Autre ville CEMAC : commune saisie manuellement et quartier « Autre » saisi librement.
5. Changer de pays ou ville : les valeurs dépendantes sont effacées, mais ne pas perdre l'adresse volontairement saisie.
6. Vérifier l'isolation RLS d'un établissement d'un autre propriétaire et la présence de la nouvelle adresse dans la fiche établissement après création.
7. Vérifier que les quatre comptes existants et leur historique restent lisibles et ne nécessitent aucune saisie rétrospective.

### Périmètre non finalisé

Le répertoire de **tous** les arrondissements, communes et quartiers de **toutes** les villes des six pays CEMAC demande une mission distincte de collecte, revue des sources et contrôle des variantes. Le parcours technique fonctionne même pour les localités encore absentes grâce à « Autre ». Ne pas présenter le répertoire partiel comme exhaustif.
