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

## Restaurant — carte et boissons propres à chaque établissement

**Chaque restaurant définit lui-même sa carte et ses prix.** Aucune carte ni aucun stock ne sont partagés entre deux établissements, même appartenant au même propriétaire.

### Carte du restaurant (administration propriétaire / personnel autorisé)

- Ajouter, modifier, masquer et réactiver les catégories (ex. plats, boissons, desserts), articles, descriptions, prix de vente en FCFA, photos facultatives, suppléments et disponibilités.
- Le propriétaire peut organiser plusieurs cartes / menus (petit déjeuner, déjeuner, soirée, menu du jour) avec leurs horaires et leurs tarifs si nécessaire.
- Aucun menu ni tarif d'exemple ne doit apparaître comme une offre réelle : chaque restaurant publie **sa propre** carte et décide des prix.
- La carte publique scannée depuis un QR de table affiche uniquement les articles publiés de **ce restaurant**, avec prix à jour et disponibilité.
- Les changements de tarif doivent préserver le prix convenu des commandes déjà confirmées; les anciennes commandes restent historiquement justes.

### Boissons (stock réel indépendant)

- Chaque boisson est une fiche vendable (libellé, format/unité, prix en FCFA, quantité en stock, stock minimum facultatif, statut actif/indisponible).
- Le responsable enregistre les entrées (approvisionnement) et les corrections de stock, avec un motif et une trace de l'auteur.
- À l'acceptation d'une commande, une quantité disponible peut être **réservée** atomiquement pour empêcher les commandes concurrentes de dépasser le stock.
- À la remise/service effectif d'une boisson, la quantité réservée est **déduite du stock réel une seule fois**, même si le paiement intervient à la fin du repas. L'annulation libère la réservation non servie.
- Aucun décrément supplémentaire lors de l'encaissement, du rafraîchissement d'écran ou d'une notification répétée. Prévoir idempotence et garde-fous serveur pour commandes concurrentes.
- À rupture de stock, la boisson est indisponible pour de **nouvelles** commandes sur le menu public; un responsable peut ajouter du stock pour la réactiver. Réglage éventuel de rupture et réapprovisionnement manuel.
- Les paiements restent des transactions distinctes : **service ≠ paiement vérifié**, et `payer à la caisse` n'autorise pas le stock à devenir fictif.

### Contraintes multi-tenant et tests

- Toutes les catégories, menus, articles, tarifs, commandes, lignes, réservations de boisson et mouvements de stock sont rattachés côté serveur à un `shop_id` valide.
- Scanner le QR du restaurant A n'affiche jamais la carte ou le stock de B. Un `menu_item_id` ou `drink_id` de B soumis au QR de A est refusé côté serveur.
- Scénarios de test : création d'une carte vide, ajout de prix, modification des prix sans rétroactivité, réception de boissons, deux tables commandant la dernière boisson, service, annulation, rupture, réapprovisionnement et historique.
- Les achats d'ingrédients et coûts des repas seront liés dans un module achats/rentabilité distinct : aucune marge précise inventée sans coût ou quantité consommée connu.
- Ne pas toucher au système de vente de vêtements existant; conserver la DA « Le Cahier ».

**Statut : spécification préparatoire, pas encore implémentée ni déployée.**

## Restaurant — commandes numérotées, table et prise de commande par serveur

**Toute commande réelle appartient à un seul restaurant** et reçoit une référence unique et lisible dès sa création effective, que la commande provienne du QR à table, d'une serveuse avec tablette/téléphone/PC, ou du comptoir.

### Une seule source de vérité pour tous les canaux

- Les commandes QR client et les commandes saisies par le personnel suivent **le même cycle métier, la même carte publiée, les mêmes tarifs, contrôles de stock, permissions, historique, caisse et notifications cuisine**. Éviter de créer deux systèmes de commandes parallèles.
- Les terminaux sont interchangeables : interface responsive tablette, téléphone et PC, éventuellement plusieurs appareils simultanés, avec mise à jour quasi temps réel. Un appareil hors réseau peut conserver un brouillon mais ne prétend pas avoir envoyé une commande au serveur sans accusé de réception.
- La fiche admin affiche en évidence le **numéro de commande**, le **numéro / nom de table**, l'heure, l'origine (`qr_client`, `serveur`, `comptoir`), le serveur si applicable, les plats et quantités, les notes, le total, l'état cuisine/service et l'état du paiement.
- Les commandes à emporter/sans table restent possibles et doivent être identifiées explicitement comme telles, jamais attribuées arbitrairement à une table.

### Numérotation fiable

- Chaque commande obtient une **clé interne UUID immuable** et un **numéro commercial lisible**, unique à l'intérieur de son établissement; l'interface admin peut afficher une référence de type `CMD-0042` en exemple, sans jamais dépendre du numéro seul pour des autorisations.
- Numérotation générée **côté serveur et atomiquement**, avec contrainte d'unicité `(shop_id, order_number)`. Plusieurs commandes simultanées doivent recevoir des références distinctes. Prévoir un identifiant d'opération (idempotence) pour éviter les doubles créations après un rafraîchissement ou un nouvel essai.
- Un restaurant A et B peuvent tous les deux avoir `CMD-0042`, mais leurs commandes restent parfaitement distinctes par `shop_id` et UUID. Dans les exports multi-restaurants, afficher également le nom et/ou code d'établissement.

### Commande prise par une serveuse

1. La serveuse se connecte à l'espace **de son restaurant** avec une identité/session autorisée sur la tablette ou le téléphone; le propriétaire attribue les droits et le compte/identifiant de personnel.
2. Elle choisit **Table 04**, puis « Nouvelle commande »; l'app affiche exclusivement la carte, les prix et les disponibilités du restaurant actif.
3. Elle sélectionne les plats, boissons, quantités et remarques (`sans piment`, `sauce à part`, etc.), puis vérifie le récapitulatif et appuie sur « Envoyer en cuisine ».
4. Le serveur enregistre atomiquement la commande, son numéro lisible, sa table et la provenance `serveur`. La cuisine/bar reçoit la commande avec une notification; l'interface propriétaire et caisse la voit aussi.
5. La serveuse suit « Reçue → En préparation → Prête → Servie », peut ajouter une **commande complémentaire** à la même table sans effacer la première, et peut demander l'addition selon ses autorisations.
6. Le client peut **également** commander en scannant le QR de sa table. Les deux canaux peuvent coexister pour une table, avec références propres à chaque commande et une addition de table éventuellement regroupée. La saisie d'une même commande deux fois est protégée par idempotence, pas par rapprochement naïf du contenu.
7. Les modifications/annulations après envoi ont des règles de permissions, d'état et un journal d'audit; les prix historiques, réservations de boissons et totaux doivent rester cohérents.

### La table ne doit jamais se mélanger

- Modèle proposé : `restaurant_tables` avec `id`, `shop_id`, `name/number`, `active`; la référence de table n'est unique **que dans son restaurant**. Les commandes référencent obligatoirement une table appartenant au même établissement lorsqu'il s'agit d'une commande sur place.
- Le QR de table résout côté serveur une liaison `shop_id + table_id` stable, et la commande manuelle doit valider les deux IDs côté serveur; le client ne peut pas modifier le restaurant ou la table en bricolant le formulaire.
- Aucune prise de commande par serveur sur un autre restaurant sans accès autorisé; changement d'établissement explicite pour les propriétaires de plusieurs entreprises.

### Paiement, stock et fiabilité

- **Commande créée ≠ paiement confirmé**. Le paiement en caisse, Mobile Money ou carte suit la politique de l'établissement (avant/après service) et la confirmation sécurisée du moyen de paiement.
- Réservation de stock de boissons à l'acceptation et déduction une fois au service, selon la règle existante; ne pas soustraire à nouveau lors du paiement.
- Notifications réelles et temps de préparation sont indicatifs; aucun statut `servi` ne signifie automatiquement `payé`.
- Doit rester conforme à la DA **« Le Cahier »** sur smartphone, tablette et PC, sans réinventer de thème sombre.

### Tests obligatoires avant déploiement

1. Deux serveuses sur deux tablettes créent simultanément des commandes différentes; chaque commande reçoit un numéro distinct.
2. Le QR de la table 4 du restaurant A et la commande manuelle de la table 4 du restaurant B restent isolés.
3. Une serveuse enregistre une commande sans QR : elle apparaît immédiatement avec table, numéro, auteur et état dans l'espace admin et cuisine.
4. La même table reçoit commande par QR et par serveuse, sans doublon, avec possibilité d'addition regroupée.
5. Le terminal perd le réseau avant confirmation : une commande non validée au serveur ne doit pas apparaître comme « envoyée »; la nouvelle tentative ne doit pas doubler la commande.
6. Deux commandes simultanées sur le dernier soda disponible ne peuvent pas réserver plus d'unités que le stock.
7. Les commandes à emporter ne sont pas artificiellement liées à une table; les corrections de serveur ne réécrivent pas l'historique de paiement.

**État : exigences documentées uniquement, fonctionnalités restaurant non implémentées ni déployées.**

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
