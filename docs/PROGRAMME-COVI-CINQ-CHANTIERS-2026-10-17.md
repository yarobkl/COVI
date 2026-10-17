# COVI — Programme d'intégration des cinq chantiers (ordre imposé)

Date de départ : 17 octobre 2026. Développements sur `feature/covi-restaurant-salon-v1` (PR brouillon 44).
**Règles absolues : aucun déploiement, aucune application de migration sur la production Supabase,
aucune fusion sans autorisation explicite. Conserver la direction artistique « Le Cahier ».**

## 1 — Restaurant (EN COURS : services, cuisine et caisse)

### Implémentation déjà livrée en branche

- Tables, menu/boissons, stocks et plan de salle; moteur de commande et sessions de table.
- Commandes collectives via QR/code de groupe, responsabilité du premier participant ayant terminé et
  confirmation finale uniquement par ce responsable; fonctions d'admission désactivées par défaut.
- Ajout à la même addition, numéro unique, mouvements de stock journalisés; encaissement espèces
  idempotent et déblocage de table après paiement complet confirmé.
- Comptes personnels Restaurant : `restaurant_staff_members`, invitations longues à usage unique,
  rôles `waiter` / `kitchen` / `cashier` et suspension immédiate des droits.
- RPC avec droits contrôlés **sur le serveur** pour ouvrir la table, délivrer le code invité,
  ajouter à l'addition, marquer un plat servi et encaisser. Un caissier ne peut pas ajouter un plat;
  un cuisinier ne peut pas encaisser. Les droits n'accordent aucun accès aux salaires.
- `restaurant_staff_room` ne renvoie que les données nécessaires au travail de la personne;
  pas de tokens des participants, données d'autres établissements, secrets QR ni salaires.
  La cuisine ne reçoit pas les montants d'encaissement.
- Journal `restaurant_staff_events` réservé au propriétaire, avec compte de l'acteur, session,
  action et horodatage. Consultation paginée dans les paramètres du restaurant.
- Espace de travail employé depuis son propre compte COVI (service/cuisine/caisse).

### Critères pour clôturer le chantier 1

- CI migrations, contrôle statique, tests d'interface et tests SQL en vert sur le dernier commit.
- Tests sur **plusieurs smartphones/tablettes** avec vrais comptes distincts :
  commandes simultanées, réseau coupé, ajout après envoi, double paiement, double clic, refus de
  mélange d'établissements, départ sans paiement et clôture.
- Revue des droits des API Edge et de toutes les fonctions `SECURITY DEFINER`,
  mise en charge, session expirée et journaux d'audit.
- Contrôle bancaire : les paiements Mobile Money ne peuvent être déclarés reçus sans vérification
  côté fournisseur; seule la réception vérifiée (ou espèces attestées en caisse) solde l'addition.
- Procédure complète d'annulation de commande, de produit manquant, d'absence de connexion et
  d'erreur sur une table; droits d'exception et audit.

## 2 — Salon de coiffure (APRÈS clôture 1)

- QR permanent unique **par salon** et page publique responsive nom, prénom, téléphone international,
  date, heure et prestation; Turnstile, quotas et protection des données.
- Agenda des coiffeurs, durée par prestation, conflits de créneaux par collaborateur,
  horaires d'ouverture, pauses, fuseau local; choix du mode de confirmation par propriétaire.
- Notification et confirmation sans déclarer un rendez-vous « confirmé » sur une simple soumission.
- Caisse des prestations, commissions des coiffeurs et produits consommables avec flux d'audit.
- Tests multi-salons, refus des réservations croisées, annulations, fuseaux et simultanéité.

## 3 — Salaires et personnel commun aux trois métiers (APRÈS clôture 2)

- Fiche employé indépendante des droits d'accès, embauche/fin de contrat,
  salaire fixe / commission / prime / avance / échéance / versement effectivement payé.
- Calcul financier en XAF précis : payé ≠ dû ≠ prévision; éviter doubles charges.
- Historique mensuel et annuel et confidentialité des données salariales,
  restauration d'un salarié désactivé sans perdre ses écritures.
- Document PDF récapitulatif interne (à distinguer des fiches de paie réglementaires).
- Vérification des règles locales de paie avant tout bulletin officiellement présenté comme tel.

## 4 — Calculs, bilans et exports Excel/PDF (APRÈS clôture 3)

- Contrat de calcul pour chiffre d'affaires **encaissé**, achats, CMV, marge, charges,
  résultat estimé, trésorerie, rémunérations, stock et pertes. Aucune confusion.
- Tout rapport indique période, fuseau, établissement, XAF, hypothèses,
  enregistrements manquants et statut des paiements.
- Agrégations SQL `numeric` / entiers XAF, bornes temporelles `[début,fin)` et
  calcul exhaustif malgré pagination ; tests 0, 1, 1 001 et 10 000 écritures.
- Exports `.xlsx` réellement typés (valeurs numériques, colonnes, filtres),
  et `.pdf` avec tableaux, sous-totaux et traçabilité.
- Totaux identiques et réconciliés avec transactions dans les trois supports :
  base, écran, export. Refuser le bilan en cas de données incomplètes.

## 5 — SaaS multi-établissements et préparation publication (APRÈS clôture 4)

- Supprimer la limite historique d'un seul commerce par propriétaire **uniquement**
  après revue des invariants d'authentification et de sélection du magasin actif.
- Isolation `shop_id` côté PostgreSQL/RLS/RPC/Edge/UI et tests comptes A/B,
  transferts internes sans double comptage, permissions et vue consolidée explicite.
- Sécurité, surveillance, plan de sauvegarde, restauration, conformité et facturation SaaS.
- Validation mobile/tablette/PC, performances, accessibilité, régressions boutiques vêtements,
  DA « Le Cahier », séquence de migration, retour arrière et préproduction.
- Mise en production uniquement après **autorisation séparée et explicite** du propriétaire.

**Un test unitaire vert n'est pas une preuve de disponibilité commerciale.**
Les étapes non livrées ci-dessus restent NON TERMINÉES jusqu'aux vérifications réelles.
