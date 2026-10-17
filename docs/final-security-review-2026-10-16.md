# COVI — Revue finale de sécurité avant toute intégration

**Date : 16 octobre 2026 — Statut : NO-GO production.**
Périmètre : branche `feature/covi-stock-central-omnichannel`, PR brouillon #22.
Cette revue concerne les changements sur la branche, **pas une certification de la production**.

## Périmètre revérifié

- Ventes catégorielles, commandes manuelles et commandes publiques QR/social ;
- identité des caissiers, prénom saisi, PIN personnel, autorisations et invitations ;
- montant négocié, reçus durables, double clic, dernière pièce, stock TEST / réel ;
- photos de référence privées, anti-robots, limitation d'abus et suivi client ;
- compatibilité avec la direction artistique « Le Cahier » et les anciennes ventes.

## Protections observées

1. `VITE_COVI_CATEGORY_CHECKOUT_ENABLED` reste désactivé par défaut.
2. Les SQL expérimentaux restent sous `supabase/sql-drafts/`, non migrés automatiquement.
3. Les opérations sensibles n'utilisent pas le prénom comme authentification :
   `auth.uid()` + appartenance boutique, puis code PIN pour les comptes caissiers.
4. Une demande publique ne confirme jamais un paiement et ne décrémente pas le stock.
5. Le serveur de commandes publiques utilise Turnstile, des limites SQL
   transactionnelles et un secret conservé côté serveur ; les RPC d'entrée
   publiques ne sont pas directement exécutables par le navigateur anonyme.
6. Les accès aux captures de référence sont protégés par stockage privé et RLS.
7. La capture JPEG est maintenant filtrée à l'entrée du serveur :
   structure des en-têtes, présence d'une trame et d'un scan, dimensions
   bornées à 4096 × 4096 et quatre millions de pixels, rejet des segments
   APP1 (EXIF/XMP), APP13 (IPTC) et commentaires JPEG.
   Le nouveau test utilise un vrai JPEG et couvre les fichiers contrefaits,
   les dimensions excessives et les métadonnées.
8. Une protection dédiée empêche les écritures directes sur les ventes de la
   nouvelle caisse associées à un reçu. Les ventes existantes sont conservées.

## Vérifications observées

- Exécution de la suite de contrôle isolée après durcissement de l'image :
  **188 tests unitaires réussis sur 188**, plus validations PostgreSQL jetable.
- Avant cette correction, les trois workflows GitHub (web/Windows, PostgreSQL,
  Supabase Auth + PostgREST local) étaient réussis sur la branche.
- Les workflows du dernier commit doivent être consultés séparément et passer
  au vert avant de considérer le contrôle terminé.
- Aucun test décrit ici ne prouve qu'une transaction Mobile Money a réellement
  été reçue : **cette confirmation reste exclusivement humaine**.

## Points encore bloquants avant toute intégration

- **Intégration :** comparer les changements récents de `main` avec la branche
  (au moment de l'audit : branche en retard de sept commits). Ne pas fusionner
  à l'aveugle.
- **Parcours de devis :** préciser et tester le traitement d'un prix client
  refusé ou rectifié, avec accord du client avant paiement. Le refus simple
  existe déjà, mais la renégociation complète n'est pas terminée.
- **Sécurité réseau :** les en-têtes IP de transfert peuvent être falsifiés
  selon le proxy amont. Vérifier l'identité de source effectivement garantie
  par l'hébergeur et la résistance aux abus réels, au-delà des quotas par lien,
  du contrôle d'origine et de Turnstile.
- **Protection des données :** définir la durée de conservation des numéros
  de téléphone, adresses de livraison et captures, ainsi qu'une procédure de
  suppression, sans altérer l'historique financier légalement nécessaire.
- **Compatibilité métier :** compléter la réconciliation des statistiques
  détaillées des ventes catégorielles avec l'historique et les rapports.
- **Tests finaux :** vraie recette tactile iPhone/Android, accessibilité,
  impression PDF, tests de charge contrôlés et simulation de panne réseau.
- **Déploiement :** soumettre les scripts SQL à une revue de migration additive,
  valider sauvegarde et retour arrière, puis obtenir une autorisation explicite
  avant tout changement Supabase, fusion vers `main` ou déploiement.

## Décision

**NO-GO : ne pas déployer, ne pas migrer et ne pas fusionner.**
COVI et GaspardNZ en production restent inchangés.
Le code durci et les tests sont réservés à la branche.
