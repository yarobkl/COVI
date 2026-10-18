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
