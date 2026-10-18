# COVI — Lot 3 : canal QR Restaurant séparé

**Date : 17 octobre 2026**  
**Branche :** `feature/covi-restaurant-salon-v1`  
**PR :** https://github.com/yarobkl/COVI/pull/44 (brouillon, non fusionnée)

## Livraison sur branche

1. **QR de table immuable et isolé**. Chaque QR token à 64 caractères appartient à une seule table d'un seul restaurant. Jamais de `shop_id` client ni d'identifiant de paiement dans le lien.
2. **Projection SQL minimale et sécurisée** (`restaurant_qr_catalog`). Résolution stricte du jeton, restaurant actif, table, capacité, état réel `free / collecting / occupied`, catégories, plats et tarifs publiés. Aucun numéro de téléphone, employé, participant, session, paiement ou données d'un autre restaurant.
3. **RPC non exécutable par anon/authenticated**, uniquement `service_role` via une Edge Function dédiée `restaurant-qr`, distincte de `public-checkout` pour les boutiques.
4. **Passerelle CORS stricte, GET seulement et fermeture par défaut** : `COVI_RESTAURANT_QR_ENABLED` doit être explicitement `true`; appels POST refusés, réponse cache-control `no-store`, validation des entrées et des données API, traitement prudent des erreurs.
5. **Page client** `#/table/<token>` sans connexion, style papier « Le Cahier », cartes du restaurant et disponibilité des boissons, distinction état libre / choix en cours / occupée. Elle affiche explicitement que les commandes QR publiques ne sont pas encore ouvertes. Aucune commande ni paiement ne peut être confirmé depuis cette page.
6. **Tests automatiques** : rejets des faux jetons et origines non autorisées, isolation des données et absence de PII dans la réponse, état du QR avant groupe, pendant choix, après soumission, puis après paiement complet. Tests portail Edge en Vitest, lien QR en TypeScript et base SQL sur PostgreSQL jetable.
7. **Non-déploiement** : aucune migration appliquée à la vraie base, aucun canal QR restaurant activé publiquement, aucune fusion et aucun changement à la caisse vêtements.

## Avant d'ouvrir les commandes collectives du client

- Fournir un **canal d'écriture invité** protégé par Turnstile et des limites par source, par QR et par session, côté serveur. Éviter toute fonction `SECURITY DEFINER` accessible directement aux visiteurs sans garde-fous.
- Lier chaque appareil à **son participant de la session courante** avec jeton opaque court-vivant, isolé de l'ancienne session. Les JWT/jetons des caissiers n'ont rien à faire dans le navigateur invité.
- Définir une barrière raisonnable contre l'accès à distance via **photo ancienne d'un QR** (invitation temporaire, contrôle serveur, approbation du responsable ou équivalent), sans bloquer les clients assis à la table.
- Le premier participant à valider son choix devient responsable **atomiquement**. Un autre client ne doit jamais envoyer la commande, même en imitant son identifiant.
- Soumission atomique et idempotente, rejet des références provenant d'autres restaurants, contrôle stock et prix sur le serveur; aucun affichage « envoyé » avant acquittement.
- Donner aux serveuses, cuisiniers et caissières **des identités, rôles et sessions autorisées côté serveur**, pas seulement un filtre JavaScript ni le JWT du propriétaire. Journal complet visible uniquement par l'administrateur.
- Caisse : paiement cash attesté par la personne habilitée, Mobile Money uniquement après vérification fournisseur, déblocage du QR **exclusivement** quand l'addition complète est clôturée dans la transaction serveur.
- Faire des tests d'ensemble multi-téléphones / multi-établissements, panne réseau, QR périmé, 2 scans simultanés, double clic, paiement partiel et stock épuisé.

## Exigences de non-régression

- La DA « Le Cahier », la caisse vêtements, le contrôle des salariés et les montants FCFA existants sont conservés.
- La fonction Edge Restaurant ne réutilise pas le jeton QR de la boutique vêtements et ne peut modifier aucune écriture de paiement ou de stock.
- Pas de lien public à partager tant que la nouvelle fonction Edge et la migration sont inactives en production.

**Statut : lot 3 terminé pour la consultation sécurisée; la prise de commande publique reste à développer.**
