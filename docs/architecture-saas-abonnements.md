# COVI SaaS — Architecture abonnements multi-boutiques (spécification V1)

Statut : **spécification validée pour conception**, aucun changement de base ni activation de facturation en production.
Décision du porteur de projet, 10 octobre 2026.

## Domaine unique et navigation par rôles — décision définitive

**Un seul domaine public pour toute la plateforme.** Le domaine exact sera choisi après vérification et acquisition ; `covi.app` est uniquement un exemple et n'est pas déclaré acquis.

- Site unique `https://<domaine-covi>/` ; aucune création de sous-domaines `app.`, `admin.` ou sous-domaines de boutiques.
- Routes sur le **même hôte** : `/login` (authentification), `/admin` (Super Admin), `/mes-boutiques` (sélection Owner), `/boutiques/:shopId/...` (gestion d'une boutique). Ces chemins sont des propositions à adapter aux routes existantes sans casser la V1.
- Après connexion, le serveur établit le rôle et les boutiques accessibles ; redirection vers l'espace correspondant. Ne jamais déterminer les droits à partir de la seule route ou de l'interface.
- Le Super Admin ne peut ouvrir ses outils qu'avec une autorisation serveur dédiée ; un Owner ne peut voir que ses propres boutiques ; un employé ne voit que les boutiques explicitement autorisées.
- La sélection de boutique est un contexte d'interface ; **toutes les opérations SQL/RPC revérifient l'appartenance à la boutique**.
- Aucun domaine ni sous-domaine personnalisé n'est nécessaire pour un Owner ou une boutique. Un Owner peut gérer plusieurs boutiques depuis la même session.
- DNS, HTTPS et déploiement Vercel restent centralisés. Prévoir des chemins de retour d'authentification compatibles avec le domaine final, sans modifier les URLs de production avant validation.

## Modèle commercial

- Devise : XAF (FCFA), montants en unités entières.
- Première boutique incluse : **10 000 XAF / mois**.
- Chaque boutique supplémentaire : **5 000 XAF / mois**.
- Total mensuel pour `n >= 1` boutiques autorisées : `10000 + (n - 1) * 5000`.
- Exemples : 1 = 10 000 ; 2 = 15 000 ; 3 = 20 000 ; 5 = 30 000 XAF/mois.
- Prix provisoires : stocker une version tarifaire et un prix figé sur chaque facture ; ne jamais recalculer rétroactivement les factures.
- Paiement initial : Mobile Money envoyé au numéro de collecte à Brazzaville, **vérifié manuellement** par le Super Admin. Aucun accès activé sur simple déclaration ou capture d'écran.
- Paiement et gestion des ventes en boutique sont deux domaines distincts : l'abonnement COVI ne doit pas apparaître dans les ventes des boutiques clientes.

## Parcours d'activation

1. Le commerçant demande un accès et communique une adresse e-mail ; le Super Admin saisit une demande d'abonnement.
2. Le commerçant paie via Mobile Money. L'administrateur rapproche manuellement le montant, le numéro de transaction, le payeur et la date avec les fonds effectivement reçus.
3. L'administrateur valide le paiement, crée/active l'abonnement et envoie une **invitation à usage unique et à expiration** via Supabase Auth. Ne jamais envoyer de mot de passe permanent ou journaliser un mot de passe provisoire.
4. L'Owner choisit son propre mot de passe, accepte l'invitation, crée sa première boutique et peut en créer d'autres dans la limite du quota payé.
5. Il sélectionne la boutique active ; chaque requête serveur vérifie son appartenance à cette boutique.

## Entités proposées (migration à concevoir, pas encore appliquée)

- `platform_admins(user_id, created_at)` : rôle global géré exclusivement côté serveur, jamais dans les métadonnées modifiables par le client.
- `owner_accounts(id, auth_user_id UNIQUE, status, created_at)` : compte commercial du client.
- `shop_memberships(shop_id, user_id, role, status, created_at)` : accès multi-boutiques ; `role` au minimum `owner`, évolution possible vers `manager` et `cashier`.
- `subscription_plans(id, code, currency, first_shop_monthly_xaf, extra_shop_monthly_xaf, active_from, active_to)` : catalogue tarifaire versionné.
- `subscriptions(id, owner_account_id, plan_id, status, shop_limit, period_start, period_end, grace_until, created_at)` : un abonnement actif maximum par Owner ; les périodes et limites sont fixées côté serveur.
- `subscription_invoices(id, subscription_id, invoice_number UNIQUE, currency, period_start, period_end, shop_limit, amount_xaf, status, created_at)` : montant figé, immuable après émission hors annulation/avoir.
- `subscription_payments(id, invoice_id, provider, provider_reference, payer_msisdn_masked, amount_xaf, currency, status, verified_by, verified_at, created_at)` : justificatif et rapprochement, référence transaction unique selon fournisseur et compte de collecte.
- `subscription_audit(id, actor_user_id, owner_account_id, action, before_state, after_state, created_at)` : journal non modifiable par les clients.
- `owner_invitations(id, owner_account_id, email, status, expires_at, accepted_at)` : aucune donnée de mot de passe ou jeton brut stockée en clair.

**Compatibilité :** analyser la structure existante `shops`, `owner_id`, `shop_id`, les politiques RLS et les RPC `record_sale`/`record_cart_sale` avant toute migration. Adapter ces propositions au schéma existant plutôt que créer des identités Owner contradictoires.

## Autorisations et isolation

- Super Admin : création d'invitations, rapprochement des paiements, activation/suspension et quotas via fonctions serveur sécurisées uniquement ; journal d'audit.
- Owner : lecture de son abonnement et gestion des boutiques autorisées ; aucune modification directe des statuts de paiement, prix, dates, quotas ou rôles Super Admin.
- Chaque requête de stock, arrivage, vente, charge et statistiques vérifie la relation utilisateur–boutique. Ne jamais se fier au `shop_id` reçu du client sans contrôle.
- Création de boutique atomique côté serveur : verrouillage du compte Owner, contrôle du quota et insertion dans la même transaction pour éviter deux créations concurrentes dépassant la limite.
- Les opérations hors connexion restent partitionnées par **utilisateur ET boutique**, jamais rejouées vers une autre boutique après changement de contexte.
- Ne pas utiliser de `service_role` dans le navigateur, le client Windows ou les applications mobiles.

## Cycle de vie

`pending_payment -> active -> grace -> suspended`, avec `cancelled` en clôture administrative.

- `pending_payment` : aucune nouvelle boutique ni écriture métier.
- `active` : écritures autorisées dans les boutiques payées.
- `grace` : durée à fixer avant implémentation ; politique d'écriture explicite et cohérente côté serveur.
- `suspended` : données conservées, lecture/export éventuellement autorisés, nouvelles écritures bloquées par la base, y compris les RPC de vente.
- Un renouvellement validé restaure l'accès sans suppression ni réinitialisation de données.
- Lors d'une réduction du quota, **ne jamais supprimer de boutique**. Prévoir sélection explicite des boutiques actives ou blocage de la réduction tant que le nombre de boutiques actives dépasse le quota.
- Une opération mise en file hors connexion pendant une période active ne doit pas contourner une suspension à la synchronisation : contrôle serveur au moment de l'envoi ; erreur permanente explicitement affichée et conservée pour résolution.

## Suppléments, facturation et dates

- Ajout d'une boutique : demande de quota +1, calcul du supplément et paiement validé avant augmentation du quota.
- Décision encore à prendre : prorata du supplément en milieu de mois ou cycle mensuel complet. **Ne pas coder une règle implicite**.
- Décision encore à prendre : date d'échéance, période de grâce, traitement des paiements partiels, taxes, annulations et remboursements.
- Horodatage en UTC ; affichage selon fuseau de la boutique. Montants en entiers XAF.
- Confirmation manuelle : double protection contre réutilisation d'une référence et double validation ; un même paiement ne peut créditer deux factures.

## Tests d'acceptation avant production

1. 1/2/3/5 boutiques : montants 10 000/15 000/20 000/30 000 XAF.
2. Owner avec quota 2 : troisième création refusée, y compris deux requêtes simultanées.
3. Deux Owners distincts : aucune lecture/écriture croisée, y compris en appelant directement les RPC.
4. Faux justificatif, référence Mobile Money réutilisée, paiement partiel : aucun accès activé.
5. Invitation expirée ou déjà utilisée : refus ; le mot de passe est choisi par l'Owner.
6. Suspension puis renouvellement : données intactes, écritures refusées pendant suspension et rétablies après activation.
7. File hors connexion : données isolées par boutique, suspension non contournée lors du rejeu.
8. Super Admin seul peut valider un paiement, modifier le quota ou réactiver un abonnement ; journal d'audit vérifié.
9. Réduction de quota : aucune suppression de données ni accès non autorisé à une boutique non couverte.
10. Prix d'une facture historique inchangé après évolution des tarifs.

## Déploiement progressif

1. Valider ce document et les décisions ouvertes.
2. Auditer le schéma réel Supabase, préparer les migrations versionnées et les tests SQL/RLS.
3. Implémenter les fonctions serveur de facturation/activation et les tests d'accès.
4. Construire le panneau Super Admin et l'onboarding Owner ; conserver les écrans V1 actuels fonctionnels.
5. Tester en préproduction avec plusieurs comptes et boutiques fictifs ; sauvegarde et plan de retour arrière.
6. **Demander l'accord explicite du porteur de projet avant toute migration ou activation en production.**
