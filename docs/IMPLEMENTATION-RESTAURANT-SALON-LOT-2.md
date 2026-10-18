# COVI — Lot 2 : commandes de table, caisse et agenda salon

> État de branche au 17 octobre 2026. **Non déployé, non fusionné, migrations non appliquées à Supabase production.**

## Ce qui est effectivement implémenté

### Restaurant — moteur côté serveur

- `restaurant_open_table` : ouvre une seule session active par table d'un restaurant (verrou SQL et index unique).
- `restaurant_add_participant`, `restaurant_choose_item` : plusieurs paniers individuels appartiennent à la même session; une modification de panier retire l'état « prêt » du participant.
- `restaurant_mark_ready` : le premier participant qui termine reçoit le rôle de responsable; la nomination est sérialisée par verrou de session.
- `restaurant_submit_group` : seul le responsable désigné peut envoyer la commande une fois tous les participants déclarés prêts; numéro `CMD-000001`, `CMD-000002` propre à chaque restaurant.
- `restaurant_staff_add_item` : ajoute à la même addition, avec horodatage et compte acteur. Pour le moment **seul le propriétaire** est habilité à appeler cette fonction; les droits des serveuses seront réalisés ensuite.
- `restaurant_mark_served` : déduit une seule fois le stock réel d'une boisson déjà réservée, écrit un mouvement de sortie non ambigu.
- `restaurant_adjust_drink_stock` : réapprovisionnement, perte ou correction de stock avec motif et historique; l'écriture directe du stock depuis le client est interdite.
- `restaurant_capture_cash` : opération idempotente de confirmation **d'espèces physiquement reçues par le propriétaire**; paiement partiel possible, mais table toujours occupée. Paiement final seulement si tous les articles sont marqués servis; clôture de la session dans la transaction de paiement. Le QR permanent reste attaché à sa table mais n'est pas ouvert publiquement.
- `RestaurantOrdersPage` : outil **interne propriétaire** pour créer et sélectionner des sessions, composer une tablée, valider le panier, servir les articles et tester les encaissements réels en espèces. Pas une interface publique multi-téléphones.

### Salon — agenda privé

- Catalogue propre à chaque salon, durées et prix par prestation.
- Demandes de rendez-vous privées avec statut, liens par salon (pas encore à partager).
- Fonction de confirmation propriétaire qui vérifie les chevauchements, sérialise les deux confirmations concurrentes et protège les transitions.
- Les formulaires publics salon sont **désactivés** tant que CAPTCHA, limitation par IP et contrôle des disponibilités ne sont pas opérationnels.

## Sécurité et exactitude

- Chaque session, participant, ligne, achat, mouvement et paiement appartient à un `shop_id`; RLS et RPC vérifient le propriétaire.
- Impossibilité de réaffecter une table, un QR ou un produit à un autre commerce.
- Les montants de vente sont stockés en XAF entiers sur des lignes à prix historique; les additions sont recalculées à partir des lignes côté serveur. Un paiement « déclaré » sur mobile n'est pas un paiement vérifié.
- Aucun état « Libre » de table non vérifié n'est présenté comme réel, ni bénéfice inventé.
- Les sorties de boissons n'ont lieu qu'au service, **pas** à l'encaissement.
- Le modèle historique vêtements et les interfaces « Le Cahier » restent préservés.

## Tests automatisés

- Migrations PostgreSQL rejouées dans une base jetable.
- Tests des références de commande, groupes, responsable désigné, stockage et paiements partiels/finals.
- Test multi-session PostgreSQL `restaurant_concurrency.sh` : deux appareils, une seule session sur la table.
- Test multi-tenant inter-établissements et contrôle du stock, ainsi que parcours RDV.
- CI web (formatage, lint, TypeScript, build, Vitest) et SQL servent de barrières avant toute fusion.

## Ce qui n'est PAS encore activé ou finalisé

1. Parcours public client restaurant (QR table → ses propres choix depuis son téléphone), session de présence, jetons sécurisés et anti-abus.
2. Droits réels des serveuses, cuisine/bar et caissière, avec PIN/session et audit nominatif admin-only.
3. Prise de commande client en direct hors compte propriétaire; ajout par scan QR en mode employé.
4. Paiement Mobile Money/carte avec preuve externe et rapprochement des encaissements.
5. Gestion d'addition séparée ou multi-moyen, remboursements/avoirs, clôture exceptionnelle autorisée et auditée.
6. Gestion des réservations publiques du salon, QR partageable, SMS/WhatsApp et capacité multi-coiffeurs.
7. Exports Excel/PDF, paie et bilans financiers intégralement rapprochés, comptabilité des ingrédients.
8. Multi-établissements par même propriétaire : encore bloqué par `shops_owner_id_uidx`, donc pas promis comme prêt.

## Condition de publication

**Interdiction de déployer, d'exécuter ces migrations sur la base de production ou d'autoriser un vrai client à payer** sans validation du propriétaire, tests de bout en bout avec comptes isolés, revue RLS/RPC, procédures de récupération et approbation explicite.
