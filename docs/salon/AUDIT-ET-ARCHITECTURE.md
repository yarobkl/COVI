# COVI Salon professionnel — audit initial et architecture

Branche : `feature/covi-salon-professional-v1`, créée depuis `main` (`3eb0bf7`, 23/10/2026).

## 1. Audit initial (avant intervention)

### Ce qui existait dans `main`

| Élément                                               | État réel                                                                                                                                                                                                                                      |
| ----------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ouverture d'un salon (`create_my_salon_with_address`) | Fonctionne : salon XAF, pays CEMAC, adresse obligatoire. Appliqué en production.                                                                                                                                                               |
| Prestations (`salon_services`)                        | Nom, prix, durée, actif. Écriture directe par le propriétaire (RLS). Pas de catégorie, description, coût, habilitation.                                                                                                                        |
| Rendez-vous (`salon_booking_requests`)                | « Demandes » : prénom, nom, téléphone, **une** prestation, statut. Saisie manuelle par le propriétaire, confirmation avec contrôle de chevauchement **pour tout le salon** (une seule personne à la fois). Aucun collaborateur, aucun horaire. |
| Lien de réservation public (`salon_booking_links`)    | Table présente, **non activée** (pas de formulaire public sécurisé).                                                                                                                                                                           |
| Personnel (`employees`)                               | Fiches RH génériques (salaire, % commission), sans lien avec les prestations ni l'agenda.                                                                                                                                                      |
| Caisse, stock, clients, finances, rapports salon      | **Absents.**                                                                                                                                                                                                                                   |
| Assistant Gemini                                      | Pour un salon : conseils généraux seulement, **aucun chiffre** (`financeAvailable: false`).                                                                                                                                                    |
| Interface                                             | 2 pages : Prestations, Rendez-vous (liste). Accueil « Bienvenue dans votre salon ».                                                                                                                                                            |

### Branches et PR comparées

- `feature/covi-restaurant-salon-v1`, `feature/covi-multisector-live-base`,
  `feature/covi-multisector-staff-foundation` : **aucun fichier salon absent de `main`**. Elles
  contiennent des versions plus anciennes des mêmes fichiers (`main` est plus complet).
- PR #52 et #53 : restaurant (activation, accueil guidé), fermées sans fusion ; leur contenu est
  arrivé dans `main` par d'autres PR. PR #61 (ouverture salon) : fermée, son contenu
  (`salon_opening_address`, `salon_owner_manual_booking`) est dans `main` et en production.

### Migrations

En production (lecture seule, vérifiée le 23/10/2026) : toutes les migrations salon de `main`
sont appliquées (`restaurant_salon_foundation`, `sector_tenant_integrity`,
`salon_booking_confirmation`, `salon_opening_address`, `salon_owner_manual_booking`).
**0 salon** existe en production. `btree_gist` est disponible mais pas installé.

Les 6 migrations de cette branche (`20261024090000` à `20261024095000`) sont **préparées, non
appliquées**.

### Risques relevés

1. Agenda actuel : le contrôle de chevauchement est global au salon (2 coiffeurs ne peuvent pas
   travailler en même temps) ; corrigé par un agenda par collaborateur.
2. Prestations modifiables directement depuis le navigateur (RLS propriétaire) : acceptable,
   conservé ; les nouvelles données ne sont jamais écrites directement.
3. Aucune trace des opérations sensibles côté salon : ajout d'un journal `salon_events`.

## 2. Architecture retenue

**Toutes les nouvelles tables** ont la RLS activée et **aucun droit direct** pour `anon` ni
`authenticated`. Tout passe par des fonctions `SECURITY DEFINER` qui commencent par
`salon_require(shop, action)` : le rôle est recalculé côté serveur à partir de `auth.uid()` ; le
`shop_id` envoyé par le navigateur n'est jamais une preuve.

| Rôle         | Droits                                                                                                                        |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Propriétaire | Tout.                                                                                                                         |
| Responsable  | Tout sauf réglages, comptes d'accès, règles et versements de commissions.                                                     |
| Caissier     | Agenda complet, clients, caisse (pas de remise, pas de changement de prix, pas de remboursement).                             |
| Coiffeur     | Ses rendez-vous uniquement ; passer « arrivé / en cours / terminé ». Pas d'annulation, pas de caisse, pas de fichier clients. |

Les comptes collaborateurs utilisent le même mécanisme que le restaurant : code à usage unique
(48 h, empreinte SHA-256 seulement, 5 essais ratés par quart d'heure).

### Tables ajoutées

`salon_settings`, `salon_opening_hours`, `salon_staff_profiles`, `salon_staff_services`
(habilitations), `salon_staff_hours`, `salon_staff_absences`, `salon_staff_members`,
`salon_staff_invites`, `salon_staff_invite_attempts`, `salon_clients`, `salon_events`,
`salon_appointments`, `salon_appointment_services`, `salon_supplies`,
`salon_supply_movements`, `salon_service_consumables`, `salon_tickets`, `salon_ticket_lines`,
`salon_payments`, `salon_commission_payouts`. Colonnes facultatives ajoutées à `salon_services`
(catégorie, description, coût direct estimé).

### Règles métier clés

- **Double réservation impossible** pour un même collaborateur : verrou de l'agenda dans la
  fonction + contrainte d'exclusion PostgreSQL (`btree_gist`), testées à deux sessions simultanées.
- Contrôles d'un rendez-vous : collaborateur actif, horaires du salon, horaires du collaborateur,
  absence du jour, habilitation à chaque prestation.
- **Le stock, les coûts et les commissions sont figés au paiement**, une seule fois par ligne
  (index uniques) ; chaque écriture d'argent porte une clé d'opération idempotente.
- **Mobile Money / carte : confirmation manuelle par la caisse** (`confirmation='manual'`). COVI
  n'interroge aucun opérateur et ne présente jamais un paiement comme confirmé par l'opérateur.
- Paiement en une fois (plusieurs moyens possibles) ; **le paiement partiel à crédit n'est pas
  pris en charge** en v1.
- Remboursement de lignes entières, motif obligatoire ; rien n'est effacé ; produit vendu remis en
  stock si demandé ; les consommables utilisés ne reviennent pas.
- Consommables : quantité paramétrée par prestation ; si le stock est insuffisant, la caisse
  n'est pas bloquée, la quantité disponible est sortie et un **écart de stock** est signalé dans
  les alertes. Un produit **vendu** exige en revanche un stock suffisant.

### Définitions financières

- **CA réalisé** : montants nets (après remise) des lignes payées dans la période, hors lignes
  remboursées. Une prestation non payée n'est jamais du CA (« en attente d'encaissement »).
- **Encaissements nets** : paiements reçus − remboursements versés dans la période.
- **Coûts directs** : consommables réellement sortis (coût moyen pondéré) ou, sans consommables
  paramétrés, coût direct estimé de la prestation ; coût d'achat des produits vendus.
- **Commissions dues** : figées au paiement, sur le montant net de la ligne ; pourcentage, montant
  fixe par prestation, ou aucune.
- **Autres charges** : `shop_expenses` de la période, **hors catégorie contenant « commission »**
  (montant affiché à part) pour ne jamais compter une commission deux fois.
- **Résultat de pilotage estimé** = CA − coûts directs − commissions − autres charges. Ni résultat
  comptable, ni bénéfice fiscal.
- **Flux de trésorerie estimé** = encaissements nets − commissions versées − autres charges −
  achats de produits enregistrés.
- **Remboursement après la clôture d'une période** : le CA, les coûts et les commissions restent
  rattachés à la **date de la vente**, hors lignes remboursées. Un remboursement tardif modifie donc
  les chiffres de la période d'origine (son CA baisse), tandis que l'argent rendu apparaît dans les
  encaissements de la période du remboursement. Une commission déjà versée sur une prestation
  ensuite remboursée laisse un **solde négatif** visible, rien n'est repris automatiquement.
  Testé dans `tests/sql/salon_pro.sql` § 11. Autre choix possible (à décider par le propriétaire) :
  déduire le remboursement dans la période où il a lieu, sans toucher aux périodes passées.
- **Périodes** : calculées dans le fuseau réglé pour le salon (`salon_settings.time_zone`), côté
  base comme dans l'écran Rapports ; une page laissée ouverte passe d'elle-même au jour suivant à
  minuit.

## 3. Recette avant activation

Couvert par les tests automatiques (CI GitHub `test-web` et `test-db`, et en local) :

- droits par rôle et isolation entre salons (`salon_pro.sql` § 1 à 8, § 6 bis : accès direct aux
  tables refusé) ;
- réservations et encaissements simultanés (`salon_concurrency.sh`) ;
- scénario financier exact, paiements mixtes, remboursement après clôture, commissions
  (`salon_pro.sql` § 9 et § 11) ;
- caisse : clé d'opération réutilisée après coupure, rafraîchissement des ventes dès le paiement
  (`TicketEditor.test.tsx`, `SalonCheckoutPage.test.tsx`) ; jour courant dans le fuseau du salon
  (`useSalonToday.test.ts`).

`test-db` installe `btree_gist` et rejoue **toutes** les migrations sur un Postgres vierge : la
migration est donc vérifiée sur Postgres, pas sur un projet Supabase.

**Reste à faire par le propriétaire, avant la production** (non réalisable depuis cette branche) :

1. Appliquer les 6 migrations sur un environnement de **staging** Supabase (branche ou projet de
   test), après `create extension if not exists btree_gist with schema extensions`.
2. Y refaire à la main : un rendez-vous, un paiement mixte espèces + Mobile Money, un
   remboursement, un rapport du mois, et un essai de connexion d'un deuxième salon (il ne doit rien
   voir du premier).
3. Décider de la règle « remboursement après clôture » (§ 2, définitions).

**Statuts à ne pas confondre** : le statut Vercel (« Preview » vert) indique seulement que le front
se construit et se déploie en aperçu ; il ne teste ni la base ni les règles métier. Ce sont les
checks GitHub `test-web` (typage, lint, tests du front, build) et `test-db` (toutes les migrations
et toutes les suites SQL) qui valident le fonctionnement. Le check Cloudflare « Workers Builds » échoue
aussi sur `main` : réglage du projet Cloudflare, sans lien avec le code.

## 4. Retour arrière

Les migrations sont additives. Pour annuler avant toute donnée réelle : supprimer les objets
`salon_*` créés par `20261024090000` à `20261024095000` (aucune table existante n'est touchée,
hormis 4 colonnes facultatives ajoutées à `salon_services` qui peuvent rester). Le front revient à
l'état précédent en annulant la PR.
