# COVI — validation isolée du parcours de caisse V1

**Ce fichier est un plan de test. Aucun des scénarios SQL n'a encore été exécuté.**
Ne jamais exécuter ces scénarios sur la base Supabase de production.

## Invariants
- Paiement reçu hors COVI (espèces, Mobile Money, autre), puis confirmation humaine.
- Première version : création, approbation et encaissement réservés au propriétaire authentifié de la boutique.
- Le prénom saisi figure sur le reçu et ne donne jamais une autorisation d'accès.
- Création et approbation : aucun mouvement de stock.
- Confirmation : vente, reçu, prénom, mouvement de stock et compteur enregistrés dans une seule transaction.
- Commandes TEST et réelles isolées. Aucun changement des anciennes tables de produits.

## Scénarios d'acceptation en base isolée
| ID | Action | Résultat attendu |
| --- | --- | --- |
| C01 | Créer une commande manuelle avec deux catégories, plusieurs prix négociés | Statut submitted, montant recalculé, stock inchangé |
| C02 | Répéter C01 avec même identifiant et ordre des lignes inversé | Même commande, pas de duplication |
| C03 | Réutiliser un identifiant avec un panier modifié | Conflit, aucune mutation |
| C04 | Deux créations simultanées avec même identifiant | Une seule commande |
| C05 | Client non connecté ou propriétaire d'une autre boutique | Refus total |
| C06 | Catégorie d'une autre boutique ou mélange stock réel/TEST | Refus total |
| C07 | 101 lignes, panier vide, quantité nulle, prix négatif, décimal ou débordement | Refus et aucune écriture |
| A01 | Approuver une commande avec stock disponible | Statut approved, auteur et date enregistrés, stock inchangé |
| A02 | Répéter approbation | Réponse idempotente, stock inchangé |
| A03 | Stock insuffisant, commande expirée ou annulée | Refus et aucune mutation |
| P01 | Confirmer manuellement un paiement reçu | Vente et reçu portant le prénom + sortie de stock une seule fois |
| P02 | Même confirmation répétée après coupure réseau | Même numéro de reçu, aucune nouvelle vente |
| P03 | Même opération avec autre prénom, mode ou référence | Conflit et aucun changement |
| P04 | Deux paiements concurrents de la même commande | Une seule vente et un seul reçu |
| P05 | Deux commandes concurrentes pour le dernier vêtement | Une seule réussit, l'autre reste non payée |
| P06 | Stock insuffisant sur la deuxième catégorie | Annulation complète de toute la transaction |
| P07 | Ventes TEST et réelles | Numéros et stocks distincts, préfixe TEST visible |
| P08 | Confirmation d'une commande soumise, réservée, annulée ou expirée | Refus |
| S01 | Tentative de mise à jour directe par le navigateur | Refus des écritures sur les nouvelles tables |
| S02 | Vérification propriétaire des fonctions SECURITY DEFINER et GRANT EXECUTE | Aucune confirmation accessible à anon ou PUBLIC |
| UI01 | Prénom composé ou accentué | Prénom conservé sur la facture ; identité du compte conservée en audit |

## Conditions avant activation
1. Exécuter les brouillons SQL dans une base PostgreSQL/Supabase **isolée**.
2. Vérifier les privilèges SQL et les courses concurrentes.
3. Lancer npm ci, npm run typecheck, npm test et npm run lint, et lire les journaux.
4. Mettre à jour le tableau de bord : les ventes par catégories n'utilisent pas l'ancien sale_items.
5. Ajouter de véritables autorisations d'employés avant de laisser un autre compte que le propriétaire confirmer.
6. Développer séparément l'entrée publique QR/social avec limitation d'abus.
7. Ne jamais fusionner, migrer ou déployer en production sans validation explicite.

## Limites du moment
Le schéma et les fonctions SQL sont des brouillons enregistrés sur la branche. Aucune base Supabase isolée n'existe encore. Le statut Vercel ne constitue pas une validation des tests SQL.
Les tests de pré-vol statiques peuvent être lancés par `node tests/sql-draft-safety.mjs`. Ils ne se substituent pas aux tests d'intégration PostgreSQL.
