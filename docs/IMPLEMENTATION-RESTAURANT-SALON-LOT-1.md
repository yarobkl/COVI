# COVI — Intégration Restaurant et Salon : état du premier lot

**Branche :** `feature/covi-restaurant-salon-v1`  
**PR brouillon :** https://github.com/yarobkl/COVI/pull/44  
**Base :** `feature/covi-multisector-live-base`, issue de la version de la caisse réellement en production.

## Fait (en branche seulement)

- Migration `20261017162500_restaurant_salon_foundation.sql` : `restaurant_tables`, `restaurant_menu_items`, `salon_services`, `salon_booking_links`, `salon_booking_requests`.
- Migration `20261017163000_sector_tenant_integrity.sql` : interdiction des réaffectations `shop_id` (y compris pour les employés) et du changement des tokens permanents de QR.
- Données isolées par `shop_id` et `business_kind`, RLS propriétaire; aucune lecture publique de données personnelles.
- Pages distinctes Restaurant : accueil, gestion des tables et capacité, plan visuel repositionnable, carte des plats/boissons/desserts, tarifs et disponibilité.
- Pages distinctes Salon : accueil, catalogue prestations/durées/tarifs, demandes de RDV privées et génération d'un token/lien propre au salon.
- Parcours boutique préservé : routes, vente, stock, arrivages et interface existants toujours accessibles **uniquement** aux boutiques.
- Style « Le Cahier » conservé via composants partagés et variables CSS du design system.
- Tests Web/TypeScript/build/lint, tests SQL de migrations et protections inter-établissements exécutés en CI de branche.

## Bloquants explicites — ne pas publier

1. La commande restaurant multi-téléphones n'est **pas** encore développée : participant, premier « J'ai terminé » comme responsable, validation collective, cuisine et ajouts successifs par plusieurs serveurs.
2. Le verrouillage `table_session` jusqu'à l'encaissement final et le déverrouillage automatique de QR dépendent d'un moteur transactionnel de caisse à construire et tester (concurrence + paiements partiels + idempotence). Les tables configurées ne présentent aucun faux statut « libre/occupée ».
3. Les stocks de boissons enregistrés dans la carte ne disposent pas encore de mouvements auditables et de déduction serveur au service; cette logique doit être sécurisée et réconciliée avant activation des commandes.
4. Le portail public salon, le formulaire « nom/prénom/téléphone/date/heure » et la génération de QR visuel partageable ne sont pas ouverts. Les RPC publiques restent **sans grant anon** : garde-fous anti-spam, disponibilité, fuseau horaire, confirmation et tests doivent d'abord être réalisés. Ne pas partager le lien au client.
5. Les paiements caisse restaurant/salon, salaires effectivement versés, rapports et exports financiers fiables sont des chantiers distincts.
6. `shops_owner_id_uidx` limite actuellement un propriétaire à **un seul** établissement dans le schéma existant. Ne pas promettre du multi-établissement avant une refonte vérifiée de `AuthGate`, de la sélection et des droits.
7. Le module `personnel` et la migration de base multisectorielle de la branche parente sont toujours préparatoires, **pas appliqués en production**.

## Ordre du prochain lot

1. Contrat SQL des sessions de table, contraintes de concurrence, paniers des participants et numéro de commande atomique.
2. Parcours client QR restaurant par table (sans identifiant d'établissement manipulable), sélection individuelle, premier choix validé → responsable, validation finale du groupe.
3. Circuit serveur propriétaire/employé autorisé et cuisine/bar, suivi des interventions conservé uniquement pour l'admin.
4. Caisse : confirmation réelle du paiement, verrouillage de session, statut en temps réel, table libérée au paiement complet **dans la même transaction**.
5. Stock boissons : réservations atomiques, mouvements horodatés et ajustements avec motif.
6. Rendez-vous salon : preuve de disponibilité, protection anti-abus, endpoint public vérifié, notifications, QR permanent.
7. Export et rapprochement financier, tests 2+ tenants, charge, cycles de table et paiements.

## Conditions de sortie

- Aucun mélange de magasins, aucune opération sur une autre boutique même par ID forgé.
- Aucune commande/paiement faussement confirmé; tous les montants en FCFA réconciliables et non arrondis arbitrairement.
- DA « Le Cahier » et boutique historiques inchangées.
- Tests SQL + CI intégration + e2e réels, plan de retour arrière et revue de sécurité.
- Autorisation explicite du propriétaire **avant migration Supabase ou promotion Vercel**.

**Statut au 17 octobre 2026 : premier lot implémenté et isolé, pas une V1 métier complète.**
