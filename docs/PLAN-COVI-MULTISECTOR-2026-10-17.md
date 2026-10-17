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

## Restaurant — verrouillage de table, compléments et paiement final en caisse

**Règle métier décidée : une table physique accepte une seule session de clientèle active à la fois. La table reste occupée et son QR public bloqué pour toute nouvelle commande client tant que la caisse n'a pas réellement validé le paiement complet de l'addition.** La serveuse authentifiée conserve toutefois la possibilité de scanner le QR de la table ou de retrouver la commande dans l'historique pour ajouter des articles à **la session en cours**, jamais pour ouvrir une deuxième session.

### Cycle normal

1. **Libre** : le QR permanent du restaurant et de la table peut être scanné par un nouveau client; la simple consultation de la carte n'occupe pas la table. L'acceptation atomique de la première commande ouvre `table_session`, crée une commande avec référence unique et marque la table `occupied`.
2. **Occupée / addition ouverte** : un nouveau scan public affiche « Table occupée, adressez-vous au personnel »; **aucune nouvelle commande publique** ne peut être créée. La serveuse connectée scanne le QR via le mode personnel (ou choisit la table / commande dans l'historique) et ajoute une ou plusieurs commandes complémentaires **à la même session**. Chaque ajout conserve sa référence de commande et s'agrège au total de l'addition; cuisine et stocks sont mis à jour selon les mêmes règles.
3. **Service terminé / à encaisser** : le client se rend à l'accueil et communique son numéro de table ou de commande. La caissière autorisée peut rechercher l'un ou l'autre, mais l'écran doit résoudre **l'établissement, la session active et l'addition complète**, avec toutes les commandes initiales et complémentaires; ne jamais encaisser par accident une commande d'un autre établissement ou une ancienne session de la même table.
4. **À la caisse** : la caissière reçoit espèces ou confirme un paiement Mobile Money / carte vérifié; une saisie côté client ne fait jamais foi. La caisse enregistre un paiement traçable et idempotent pour la session, rattache les montants réellement encaissés et émet le reçu.
5. **Paiement complet confirmé** : dans la même transaction serveur que la clôture de l'addition, marquer `table_session=closed_paid`, `table=free`, et invalider tout contexte ou jeton de session client antérieur. **Le QR physique ne change pas** : son identifiant opaque continue de désigner cette table, et le prochain client peut ouvrir une nouvelle session avec son prochain scan.
6. **Paiement incomplet, refusé, en attente ou non vérifié** : la table reste occupée, le QR public reste verrouillé, et aucun autre client ne peut créer de commande. La caisse peut traiter des paiements partiels si ce mode est prévu, mais seule l'extinction du solde dû libère la table.

### Déclenchement automatique depuis la caisse (règle impérative)

- L'action autorisée **« Valider l'encaissement »** dans la caisse est le **déclencheur unique du déverrouillage automatique**, sous condition que le paiement soit réellement reçu/vérifié et que **le solde de toute la session de table soit nul**, y compris les boissons et plats ajoutés ultérieurement. Valider une seule commande sur une table qui en a plusieurs ne suffit pas.
- Le serveur traite sous **une même transaction atomique** la confirmation du paiement, le contrôle final du total et des ajouts concurrents, la clôture `closed_paid` de la session et le passage de la table en `free`. Aucun bouton « Débloquer QR » ni action distincte de la serveuse n'est nécessaire.
- Dès la validation réussie, COVI **émet un événement de mise à jour de la table** : l'écran caisse, la tablette de la serveuse, le PC et le QR public reflètent le nouvel état, via temps réel et relecture fiable côté serveur. Le QR imprimé reste identique, mais l'ancienne session ne peut plus commander.
- Tant que la validation du paiement est refusée, partielle, sans accusé du serveur ou non vérifiée, le QR reste bloqué côté serveur. Un réseau interrompu ne doit jamais libérer localement la table par simple optimisme de l'interface.
- Tester la course entre un ajout de boisson et l'encaissement : transaction verrouillée / contrôle de version; soit l'ajout est pris en compte dans le montant à payer, soit il est refusé comme trop tardif. **Aucune commande ne doit être oubliée dans le total** et aucune table ne doit être libérée avec un impayé.
- Tester deux clics de paiement, reprise après panne réseau, paiement non confirmé et consultation simultanée sur deux tablettes : pas de double encaissement, pas de double clôture, aucun QR public déverrouillé trop tôt.

### Modèle et contrôles serveur proposés

- `restaurant_tables (id, shop_id, table_number, ...)` : QR permanent unique pour (établissement, table); `table_number` est un libellé humain, pas une clé globale.
- `restaurant_table_sessions (id, shop_id, table_id, status, opened_at, closed_at, ...)` : **une seule session ouverte par (shop_id, table_id)**, garantie par index unique partiel / transaction verrouillée. Une table libre peut avoir un long historique de sessions fermées.
- `restaurant_orders (id, shop_id, table_session_id, order_number, source, staff_id, ...)` : une session peut recevoir plusieurs commandes, chaque commande obtient une référence serveur unique par restaurant. L'encaissement recherche soit `table_number`, soit `order_number`, et associe tous les ajouts de la même session.
- `restaurant_session_payments (id, shop_id, table_session_id, amount, method, external_reference?, verified_at, cashier_id, idempotency_key, ...)` : paiements réellement confirmés distincts des commandes. Une somme d'encaisses confirmées `>=` total final dû est nécessaire à la fermeture, avec gestion explicite des remises/avoirs.
- Toute création de commande, tout ajout, toute fermeture et toute libération sont **atomiques et autorisés côté serveur**, indépendamment du statut affiché dans le navigateur. Une nouvelle requête concurrente échoue si table déjà occupée.
- QR public et scan par serveuse peuvent utiliser le **même QR imprimé**, mais avec contrôle du rôle et de la session : un visiteur sur ce QR d'une table occupée est bloqué; un membre de ce restaurant connecté et autorisé peut accéder à la session courante pour l'enrichir.
- Le QR ne contient ni numéro de téléphone, ni nom client, ni identifiant de session actif; seul le serveur résout un jeton opaque stable vers `shop_id + table_id + purpose`.
- Dépenses, stocks de boissons, historique cuisine et commissions éventuelles conservent une piste d'audit : un ajout n'est jamais une deuxième session indépendante, et clôturer le paiement ne décompte pas de nouveau le stock.
- Prévoir une procédure **responsable** documentée pour annulation/sortie exceptionnelle sans encaissement (client parti sans payer, erreur de table, panne), avec droits stricts et journal d'audit; ne jamais présenter un départ sans paiement comme une clôture payée.
- La tablette, le téléphone et le PC présentent les mêmes données de session en temps réel. Sans accusé serveur, ne pas prétendre qu'une commande ou un paiement a été enregistré.

### Tests d'acceptation obligatoires

1. QR Table 04 libre → nouvelle commande `CMD-0042` → Table 04 occupée immédiatement à l'acceptation.
2. Deux clients scannent simultanément la même table libre : une seule session peut être ouverte; le second voit la table occupée.
3. Sur Table 04 occupée, un nouveau visiteur ne peut soumettre aucune commande par QR, y compris en réutilisant un ancien lien.
4. La serveuse authentifiée scanne Table 04 occupée → ajoute une boisson; le même résultat est obtenu par recherche dans l'historique. La cuisine et l'addition reflètent l'ajout.
5. En caisse, rechercher « Table 04 » ou « CMD-0042 » retourne **la même session** et le total de l'ensemble de ses commandes; une ancienne session Table 04 n'est pas choisie.
6. Paiement non vérifié, partiel ou rejeté → table bloquée; paiement entièrement confirmé → clôture atomique, reçu, table libre.
7. Après paiement, le même QR physique permet une nouvelle session de table; un ancien contexte client ne peut plus modifier l'ancienne addition.
8. QR restaurant A ne peut ouvrir, enrichir ou encaisser une session du restaurant B; un employé de B ne peut pas modifier A.
9. Les doubles clics, retries réseau et notifications répétées ne doublent ni commandes, ni paiements, ni décréments de stock.
10. Sur tablette, téléphone et ordinateur, caissière, serveuse et cuisine voient les changements après confirmation serveur sans affichage trompeur.

**État : règle métier confirmée et documentée; aucun verrou de table ni flux de paiement restaurant n'a été développé ou déployé.**

## Restaurant — commande collective sur plusieurs téléphones, places et interventions multi-employés

### Capacité de la table et présence réelle

- Le restaurateur définit ses propres tables (numéro, salle/zone, capacité indicative, statut actif). Exemple : table 04, 4 places.
- La capacité **n'est pas un quota de commandes ni un seuil bloquant pour la validation** : un seul client peut occuper une table de 4; deux clients aussi. Certains convives peuvent ne rien commander.
- Le **nombre de clients présents** est une donnée séparée, modifiable par le personnel autorisé et facultativement confirmée par les clients. Ne pas confondre capacité, nombre de téléphones, nombre de participants et nombre de plats.
- Une personne peut commander pour deux convives sur un téléphone, ou un convive peut commander depuis plusieurs appareils; aucun compte ni téléphone unique n'est imposé au client.

### Session collective et panier partagé

- **Table libre** : le premier visiteur peut afficher le menu. Dès l'ouverture effective du groupe (premier ajout en panier enregistré ou ouverture par le serveur), COVI crée une seule session de table `collecting` et réserve la table à ce groupe.
- **Collecte des choix** : plusieurs clients scannent le **QR permanent de la même table en parallèle** et rejoignent la même session `collecting`; leurs choix s'enregistrent sans écraser les autres. Chaque appareil reçoit un jeton de participant lié à **cette session précise**, non à une nouvelle table.
- Un participant peut modifier sa propre sélection tant que le panier collectif n'a pas été envoyé; la somme affichée et l'état « a terminé » se mettent à jour en temps réel. En cas de coupure réseau, expliquer que l'ajout n'est pas synchronisé plutôt que l'afficher comme confirmé.
- La table affiche le panier commun (quantité, plats, options, total) et, sans demander d'identité civile obligatoire, peut distinguer « choix 1 », « choix 2 » ou des prénoms facultatifs. Les autres clients voient les choix nécessaires au récapitulatif, **jamais** les identifiants ou droits des employés.
- **Validation du groupe** : les convives peuvent indiquer « J'ai terminé mon choix ». Quand les personnes présentes sont prêtes, un participant coordinateur désigné ou une serveuse autorisée valide **la commande commune entière**. Ne jamais attendre 4 confirmations parce que la table possède 4 places; ne jamais supposer que le nombre de smartphones égale le nombre de convives.
- À la soumission, vérifier et figer atomiquement tous les choix acceptés et les tarifs en vigueur, affecter la référence `CMD-xxxx`, envoyer les tâches cuisine/bar, passer la session en `submitted/open_bill`, et interdire de nouveaux ajouts publics. Prévoir une confirmation explicite avant envoi, et une clé d'idempotence pour éviter le double envoi.
- Les participants déjà admis à la session peuvent continuer à consulter le suivi/la note, mais **ne peuvent plus envoyer de nouveaux articles directement** après validation. Pour les ajouts, ils demandent à une serveuse (règle de la caisse maintenue).
- Le QR imprimé reste permanent. Pendant `collecting`, il accepte des convives rejoignant le groupe existant, **pas la création d'un second groupe**; après `submitted`, il affiche « Table occupée, contactez le personnel » aux nouvelles visites publiques. Un jeton de participant antérieur ne permet jamais d'ouvrir une commande concurrente ni de modifier la note après validation.
- Pour éviter qu'un tiers ayant une photo du QR rejoigne/perturbe la session, le droit d'ajouter au panier de groupe doit être lié à la session courante (jeton temporaire d'adhésion / contrôle de présence ou validation serveur), expiré à l'encaissement. Ne pas se contenter d'un simple `shop_id` ou `table_id` saisi par le navigateur. Spécifier le mécanisme anti-intrusion lors du prototype sans rendre le scan pénible.
- Les contraintes de concurrence sont vérifiées côté serveur : transaction / index unique d'une session ouverte par (restaurant, table), identifiants de ligne/participation et mises à jour atomiques ou versionnées. Aucun appareil ne doit écraser le panier d'un autre.

### Modifications par plusieurs serveurs, traçabilité réservée au propriétaire

- Toute serveuse authentifiée et **habilitée dans ce restaurant** peut scanner le QR de la table occupée en mode personnel, ou rechercher la session par table/numéro dans l'historique. Elle ajoute des articles **à l'addition déjà ouverte**.
- Tous les ajouts, même réalisés par plusieurs serveurs, appartiennent à **la même session / addition** et conservent la référence principale visible `CMD-xxxx`. Chaque ajout génère une opération/ticket complémentaire interne traçable pour la cuisine; les nouveaux articles ne sont pas confondus avec ceux déjà préparés. Le paiement final regroupe tous les ajouts et commandes.
- Chaque opération possède son auteur vérifié : personne ayant saisi, modifié, annulé, commencé ou terminé une préparation, apporté un plat, servi, et encaissé. Une même commande peut ainsi contenir des lignes gérées par plusieurs serveuses et plusieurs préparateurs.
- **Seul le propriétaire/admin autorisé** consulte l'historique nominatif complet des intervenants, horodatages, modifications et responsabilités. Les clients ne voient pas les identités des employés; les serveurs et préparateurs ne disposent que des informations opérationnelles nécessaires et de leurs propres actions, sans consulter le journal nominatif complet.
- Garder distincts : **saisie de commande**, **préparation cuisine/bar**, **service**, **encaissement**. La responsabilité n'est pas attribuée automatiquement à la première personne qui a touché la commande.
- En cas de suppression/annulation ou de modification d'un article déjà envoyé en cuisine, règles de droits/état et événements correctifs visibles en cuisine : ne jamais remplacer silencieusement la commande ou masquer un article préparé.

### Paiement et réinitialisation à l'encaissement

- Une validation de caisse doit contrôler le **solde de l'ensemble de la session**, y compris les ajouts des serveuses, puis clôturer la session, libérer la table et réautoriser automatiquement le QR pour le prochain groupe dans la même transaction.
- Aucun code QR n'est régénéré à chaque passage. Après clôture, toutes les autorisations de participants de l'ancien groupe expirent et l'historique des intervenants reste archivé pour l'administrateur.
- Pendant `collecting`, `submitted`, `preparing`, `served`, ou `payment_pending`, la table n'est **jamais** réattribuée à un autre groupe; seuls les accès déjà admis et les équipes autorisées sont servis selon leurs permissions.

### Scénarios de recette obligatoires

1. Table de 4, 1 seul convive : soumission possible immédiatement sans 3 participants manquants.
2. Table de 4, 2 convives sur 2 téléphones : chacun ajoute en parallèle, prix et quantités consolidés; soumission commune par participant coordinateur ou serveur.
3. Table de 4, 4 convives dont un ne choisit rien : validation possible sans plat ou « prêt » obligatoire pour chacun.
4. Deux téléphones font un ajout simultané au même panier : toutes les lignes subsistent, aucun écrasement.
5. Deux scans simultanés de table libre : une seule session collective est créée; aucune deuxième addition.
6. Avant validation, un nouveau participant peut rejoindre le groupe autorisé; après validation, le QR ne laisse plus un nouveau client ouvrir/compléter la note.
7. La serveuse A ajoute une boisson par scan; la serveuse B ajoute un dessert depuis l'historique; une troisième personne prépare, une quatrième encaisse : une seule addition, traçabilité de chaque intervention visible à l'admin seulement.
8. Tentative non autorisée de joindre une session avec un ancien lien, avec un QR d'un autre restaurant ou avec des droits d'employé d'un autre établissement : refus serveur.
9. Dernière boisson disponible commandée simultanément depuis deux appareils : jamais de sur-réservation; correction d'affichage.
10. Paiement complet final : session clôturée et QR immédiatement disponible pour le groupe suivant; anciens participants ne peuvent plus toucher la nouvelle session.

**Statut : règles de conception ajoutées; pas encore développées, aucun déploiement ni changement SQL en production.**

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
