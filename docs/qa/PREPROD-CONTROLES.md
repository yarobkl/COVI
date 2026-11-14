# COVI — Contrôles indépendants de préproduction (GPT-06)
**Statut : protocole à exécuter par CLA-02/CLA-07 et à contre-vérifier par GPT-06. Aucun PASS déclaré à ce stade.**

## Périmètre et garde-fous P0
- **Identifiant de préproduction autorisé : `stcsjwxmmxnjwisqkudz`**. Identifiant de production **interdit** : `bmbwmwgfzrijglzcgjut`.
- Avant toute commande d'écriture, afficher le **Reference ID cible**, puis abandonner si différent. Les captures de vérification ne doivent jamais montrer une clé secrète.
- Aucun dump / clonage de production, aucune information personnelle réelle. Deux établissements factices A/B avec comptes fictifs distincts et références clairement marquées TEST.
- Si les environnements Vercel et Supabase ne peuvent pas être reliés avec preuve de configuration **et vérification à l'exécution**, **NO-GO** pour les essais d'écriture.
- Protéger les clés secrètes côté serveur, ne jamais insérer de clé service-role dans le bundle client ; utiliser uniquement une clé publique adaptée au front.

## QA-01 — Liste des migrations et dépendances
1. CLA-02 produit la liste ordonnée des fichiers de migration du dépôt + les versions **effectivement présentes** en préproduction.
2. Vérifier extension `btree_gist` avant les contraintes d'exclusion du Salon ; aucune application de migration suivante après un échec.
3. Lister les objets critiques par métier : tables, fonctions, index, contraintes, politiques RLS, droits EXECUTE.
4. Documenter décalages entre schéma courant et migrations attendues ; ne jamais marquer « vert » sur l'intention seule.

## QA-02 — Étanchéité multitenant et rôles
- Boutique A vs B : refus de SELECT/UPDATE/INSERT sur stocks, ventes, commandes, rapports.
- Restaurant A vs B : impossible d'agir sur table et commande de B par UUID connu.
- Salon A vs B : aucune visibilité sur clients, agenda, tickets ou commissions de B.
- Test de rôles : propriétaire, responsable, caissier, coiffeur, inconnu ; notamment interdiction au coiffeur de rembourser ou d'exporter clients.
- Revérifier les RPC `SECURITY DEFINER` (propriétaire autorisé côté serveur, `search_path` restreint, aucune fuite de données, privilèges EXECUTE minimaux).
- Ne pas confondre `TO authenticated` et preuve d'appartenance à une boutique : les deux sont nécessaires.

## QA-03 — Recette E2E et transactions
- Faire exécuter RET-001..010, RES-001..012, SAL-001..014, FIN-001..006 selon fonctionnalités effectivement actives.
- Pour chaque scénario : préconditions, résultat attendu/observé, preuve serveur, données avant/après, PASS/FAIL/BLOQUÉ, version du commit testé.
- Cas impératifs : double clic / relance, concurrence, remboursement, stock insuffisant, déconnexion et accès inter-tenant.
- Vérifier les opérations sur deux appareils simulés, pas seulement un rendu statique.
- Le QR public doit être limité aux actions **expressément activées** et ne pas exposer données privées.

## QA-04 — Interface et accessibilité
- Versions précises des PR #64 et #66 intégrées, captures 390 px et 1280 px sur plusieurs métiers.
- Aucune zone tactile <44 px ; aucune superposition de chiffres importants ; titres, montant, références de vente visibles.
- Salon : les 13 écrans signalés par Claude sont à revoir sur la **branche d'intégration réellement liée à la base de test**, avec données.
- Vérifier une véritable impression de QR avant de déclarer l'impression finale validée.

## QA-05 — CI, déploiement et retour arrière
- Exiger les liens vers tests web/db/e2e, migrations, version déployée, revue indépendante.
- Vérifier séparément l'échec Cloudflare (statut déjà signalé comme antérieur) et son éventuel impact sur l'architecture effective ; **ne pas ignorer aveuglément un check rouge**.
- Plan de retour arrière documenté par CLA-07, adapté aux migrations additives et aux données écrites ; pas de rollback destructif.
- Aucune fusion dans `main` ni déploiement en production avant autorisation écrite du propriétaire.

## Registre QA (à renseigner)
| Contrôle | Responsable exécution | Preuve attendue | État |
| --- | --- | --- | --- |
| Environnement cible et secrets | CLA-02 | Identifiant projet + connexion effective vérifiée sans secret | À faire |
| Migrations ordonnées Salon + dépendances | CLA-02 | Liste des versions réellement appliquées | À faire |
| RLS inter-boutiques | CLA-02 | Résultats tests négatifs A/B | À faire |
| Recette transactions | CLA-03, CLA-04, CLA-05 | Fiches RET/RES/SAL et FIN | À faire |
| Refonte en conditions réelles | CLA-06 | Captures mobile/bureau | À faire |
| E2E et CI | CLA-07 | Liens d'exécutions versionnées | À faire |
| Avis GO/NO-GO indépendant | GPT-06 | Rapport motivé | Bloqué tant que preuves absentes |

**Observation d'accès (24/10/2026) :** les lectures du projet `stcsjwxmmxnjwisqkudz` depuis le connecteur Supabase de ChatGPT ont renvoyé « You do not have permission to perform this action ». Cela ne prouve ni une installation manquante ni un échec de Claude ; simplement, GPT-06 n'a pas accès à cette cible. Les preuves devront être déposées par CLA-02/CLA-07.
