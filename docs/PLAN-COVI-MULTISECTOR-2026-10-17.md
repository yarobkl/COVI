# COVI — Feuille de route multisectorielle (17 octobre 2026)

## Décision de produit

COVI devient une plateforme de gestion de petites entreprises, tout en préservant le parcours boutique existant. Le socle commun traite comptes, établissements, personnes, permissions, ventes, charges et analyses. Les modules métier traitent des objets différents : **articles**, **prestations**, **commandes / ingrédients**. Ne jamais réutiliser artificiellement `products` pour représenter une coupe de cheveux ou un plat cuisiné.

## Constats du 17/10, lecture seule de Supabase

- 4 comptes/auth et 4 établissements, dont 3 nouveaux comptes (2 le 12 octobre, 1 le 17 octobre).
- Schéma `shops` mono-établissement dans l'interface; `AuthGate` utilise `.limit(1).maybeSingle()`.
- `shop_members` = 0 et `shop_cashier_profiles` = 2 : une identité de caissier n'est pas un contrat salarié.
- `shop_expenses` stocke des charges génériques, mais aucune paie n'est associée à une personne.
- Les produits, ventes, arrivages, frais existants et utilisateurs doivent rester intacts.

## Version préparatoire, branche non fusionnée

1. Introduire `shops.business_kind` : `retail`, `restaurant`, `salon`; défaut `retail` pour toutes les boutiques actuelles.
2. Ajouter une RPC d'inscription multisectorielle **atomique**, en conservant les anciennes RPC pour la rétrocompatibilité.
3. Créer les fiches `employees` privées : identité fonctionnelle, rôle, rémunération fixe, taux éventuel de commission, statut. Aucun compte de connexion obligatoire. **Aucune fiche salariée dans `shop_members`**.
4. Écran propriétaire « Personnel » : effectif, masse salariale fixe prévue, ajout et désactivation. La paie réellement versée viendra dans une étape dédiée.
5. Ajout du choix du secteur à l'inscription; libellés adaptés à l'activité. Les parcours métiers spécifiques resteront soumis à validation avant lancement.

## Suite de la construction

- **Phase A — Personnel / finances** : avances, versements, primes, calcul des commissions, historique et dépenses associées atomiquement, sans double comptage; rôles et permissions.
- **Phase B — Salon pilote** : catalogue des prestations, durée, tarifs, agenda, affectation coiffeur, prestations terminées, encaissements et éventuelles commissions.
- **Phase C — Restaurant pilote** : carte, variantes, prise de commande, tickets, tables, état cuisine, sur place / emporté / livraison, factures non officielles.
- **Phase D — Stocks restaurant** : ingrédients, unités, recettes, déductions et pertes. Séparer coût théorique, coût réel et bénéfice estimé.
- **Phase E — Multi-établissements** : un propriétaire peut choisir explicitement son établissement actif. Toutes les requêtes et mutations sont strictement isolées par établissement.
- **Phase F — Validation pilote** : trois vrais clients volontaires, observations des flux quotidiens, sauvegarde/retour arrière, performance mobile et accessibilité.

## Invariants de sécurité et de gestion

- Ne pas exposer les rémunérations aux caissiers ou employés : propriétaire autorisé uniquement, RLS `shop_id` + `auth.uid()`.
- Une fiche employé ne prouve pas une embauche conforme; COVI n'émet pas de bulletin officiel sans cadrage local.
- Éviter le stockage inutile de données personnelles. Archiver plutôt que supprimer les employés avec une histoire financière.
- Les versements = dépenses **seulement lors du paiement effectif**; un salaire prévu n'est pas un salaire versé.
- Devise XAF préservée; ne pas simuler de conversion FX ni de charges sociales.
- Aucun DDL SQL lancé sur Supabase en production avant approbation, aucune fusion sur `main`, aucun déclenchement manuel de Vercel.

## Critères d'acceptation avant mise en production

- Les 4 comptes et toutes les données antérieures sont inchangés.
- Pour une nouvelle boutique, le parcours initial produit/stock/ventes se comporte comme avant.
- Choisir restaurant ou salon est enregistré et récupéré après reconnexion; aucun menu « ballons » visible dans le module métier final d'un salon ou restaurant.
- Un employé est créé, désactivé et compté correctement, sans accès aux données d'un autre établissement.
- Tentatives non authentifiées et d'accès d'un autre propriétaire refusées par RLS.
- Tests de types, lint, tests unitaires et e2e des 3 parcours au vert.
- Les migrations sont revues sur base de test avec plan de restauration avant publication.

## Principe non négociable — QR codes isolés par établissement

**Un QR code = un établissement précis + un usage précis.** Cela concerne la boutique de vêtements, le restaurant et le salon de coiffure, y compris lorsqu'un seul propriétaire possède plusieurs établissements.

- Le QR code salon « Prendre rendez-vous » appartient à un seul salon. Le client peut saisir nom, prénom, téléphone, date et créneau souhaités. La demande, la disponibilité et la notification sont enregistrées exclusivement dans le calendrier de ce salon.
- Le QR code restaurant « Commander » appartient à un seul restaurant. Un QR placé sur une table est également attaché à cette table **de ce restaurant uniquement**. La carte, les commandes, la cuisine, la caisse et le stock se rapportent au même établissement.
- Les QR boutique / commande / paiement appartiennent à la boutique concernée. Un code destiné à réserver ne doit jamais pouvoir agir comme un code d'encaissement.
- Un propriétaire multi-établissements génère et retrouve des QR distincts dans la fiche de **chaque** établissement. La duplication involontaire, la réaffectation et la confusion de tableaux de bord sont interdites.
- Chaque QR possède un identifiant opaque, unique, aléatoire et révocable. Le serveur résout cet identifiant vers une association immuable `shop_id`, `purpose` et, si nécessaire, `table_id`; les paramètres `shop_id` soumis par le navigateur public ne sont **jamais** considérés comme autorité. Il faut vérifier que toute table, prestation, horaire, demande, panier ou paiement appartient au même établissement.
- La lecture et l'écriture côté propriétaire/équipe sont soumises aux permissions et à l'isolation multi-tenant; aucune autre boutique ne doit voir les noms, téléphones, rendez-vous, commandes ou ventes d'autrui. Le QR ne contient aucune donnée personnelle du client.
- La confirmation des paiements reste distincte de la création d'une commande ou réservation : un QR ou une déclaration « payé » ne certifie pas un paiement bancaire ou Mobile Money.

### Vérifications obligatoires avant déploiement

1. Scanner le QR du salon A n'affiche et n'enregistre des rendez-vous **que** pour A, même si le même compte possède un salon B.
2. Essayer de substituer l'identifiant du salon B, d'une prestation étrangère ou d'un autre créneau est refusé côté serveur.
3. Un QR restaurant de la table 4 ne peut pas créer de commande à la table 4 d'un autre restaurant.
4. Un QR de réservation ne peut déclencher ni paiement ni vente, et inversement.
5. Révoquer ou régénérer un QR invalide l'ancien code sans modifier les QR des autres établissements.
6. Les notifications, agendas, historiques et stocks filtrent par `shop_id`, sans fuite entre entreprises.
7. Le scan et la demande de réservation ne requièrent pas la création d'un compte COVI pour le client; anti-abus et protection des données sont prévus.

**État** : exigence et tests spécifiés uniquement; aucun générateur de QR salon n'est déployé.

## Statut

En préparation. Le code de cette branche ne vaut pas approbation de déploiement.
