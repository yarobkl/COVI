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

## Statut

En préparation. Le code de cette branche ne vaut pas approbation de déploiement.
