# COVI — Cartographie commerciale et intelligence territoriale (chantier réservé)

**Décision produit du 13 octobre 2026 : À PRÉPARER, NON DÉPLOYÉ.**
**Propriétaire fonctionnel : Super Admin COVI.**
**Signature : « COVI — Le système d’exploitation de votre commerce. »**

## Vision

COVI Commerce sert au commerçant à piloter ses arrivages, ses stocks, ses ventes, ses dépenses et ses bénéfices. COVI Intelligence sera, dans une version future, un observatoire géographique **des commerces inscrits sur COVI**. Exemple d'analyse : nombre de boutiques de prêt-à-porter inscrites dans le secteur de Poto-Poto à Brazzaville, puis comparaison avec Moungali. Cela ne prétend pas mesurer tous les commerces de la ville ni définir seul une vraie zone de chalandise (il faudra des données démographiques, flux et terrain complémentaires).

## Déjà prévu dans la version commerçant (sans carte)

- Pays → ville → quartier ou secteur : sélection obligatoire lors de la création de chaque **nouvelle** boutique. Les comptes historiques complètent leur fiche sans blocage.
- Suggestions initiales par ville, sélection « Mon quartier n'apparaît pas » puis saisie libre pour toute localité manquante.
- Stockage dans `shops.neighborhood` ; `shops.city`, `shops.country` sont déjà présents.
- Position GPS **facultative**, explicitement sollicitée par clic quand la personne se trouve dans la boutique : `shops.latitude`, `shops.longitude`, `shops.location_accuracy_m`. Le GPS natif du téléphone ne nécessite ni Google Maps ni clé payante.
- La donnée est privée, accessible selon les règles RLS du propriétaire de la boutique. **Aucune publication de coordonnées précises à d'autres commerçants.**
- La sélection de Poto-Poto/Moungali dans la première liste peut désigner un **arrondissement ou secteur**, pas nécessairement un quartier administratif exact. Prévoir plus tard un référentiel hiérarchique vérifié `Pays → Ville → Arrondissement/commune → Quartier → emplacement GPS`, sans assimiler arbitrairement les niveaux.

## Version future — carte interactive

1. **Fond de carte :** MapLibre GL JS + OpenFreeMap (service gratuit au moment du choix, sans garantie de disponibilité). Vérifier conditions d'usage, attribution OpenStreetMap, couverture et disponibilité avant mise en production. Prévoir un fournisseur de repli et une stratégie de cache conforme à la licence.
2. **Expérience commerçant :** ouvrir la carte centrée sur sa ville/son secteur, utiliser son GPS si souhaité, déplacer une épingle pour pointer précisément le local, afficher la précision et enregistrer les coordonnées explicitement confirmées. Permettre la modification et la suppression ; accepter la localisation textuelle sans GPS.
3. **Sécurité et consentement :** demander l'autorisation avant toute géolocalisation, ne pas géolocaliser silencieusement, ne pas collecter le domicile, informer de la finalité et de la visibilité des données. Déterminer base légale, durée de conservation et droits applicables avec la politique de confidentialité.
4. **Super Admin exclusivement :** carte privée des boutiques inscrites, filtres par pays/ville/arrondissement/quartier/activité/catégories commercialisées, compteurs, agrégats et évolution temporelle. Autorisation vérifiée côté serveur et en base, jamais sur `user_metadata` modifiable. API administrateur sécurisée, audit et limitation des exportations.
5. **Cartographie géographique :** géométrie PostGIS ou équivalent, regroupement de points, filtrage par rayon, cartes de chaleur. Ne pas identifier ni partager les revenus, le stock et l'activité individuelle des commerçants à des tiers ; ne montrer aux commerçants, le jour venu, que des statistiques agrégées respectant un seuil d'anonymat suffisant.
6. **Référentiels territoriaux :** nomenclature vérifiée pays/villes/communes/quartiers avec variantes orthographiques, suivi des localités non répertoriées, et qualité de géocodage. Aucun service public Nominatim/OpenStreetMap ne doit être utilisé massivement sans respecter sa politique.
7. **Couverture métier :** demander une activité principale et des catégories secondaires standardisées (vêtements, chaussures, alimentation, cosmétique, etc.), sans extraire les produits vendus pour un usage extérieur non expliqué.
8. **Analyses zones de chalandise :** indicateurs de densité et concurrence uniquement parmi les commerçants inscrits, couverture et biais signalés ; possibilité future d'utiliser des jeux de données locaux supplémentaires sous droits adaptés.

## Ordre de livraison

- **Étape A — en cours/prochaine livraison commerçant :** pays, ville, quartier, position GPS native facultative ; sans carte.
- **Étape B — prochaine mise à jour géo :** référentiel officiel quartiers/communes, cartographie MapLibre/OpenFreeMap côté utilisateur avec épingle et confirmation.
- **Étape C — version Super Admin privée :** vue carte des boutiques, catégorisation commerciale, filtres et analyses agrégées.
- **Étape D — plus tard :** outil d'implantation commerciale pour aider les utilisateurs, avec protections de confidentialité et périmètres d'agrégation.

## Garde-fous de livraison

**NE PAS FUSIONNER CE CHANTIER AVEC `main` SANS NOUVEL ACCORD EXPLICITE.**
Ne pas activer de carte publique, ni de carte concurrentielle côté commerçant, ni de clés payantes Google Maps. Ne pas toucher au checkout QR, aux paiements, aux stocks, à la production Supabase ou Vercel pour ce chantier. Ce document sert de spécification durable de la vision géographique COVI.
