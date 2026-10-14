# COVI — reprise de mise en production

## Autorisation et périmètre — 14 octobre 2026

Le propriétaire a explicitement autorisé dans la conversation la fusion dans main,
les migrations nécessaires et le déploiement en production. L'exigence précédente
d'une troisième base gratuite est levée. Ne pas toucher aux autres projets,
supprimer les données commerciales, engager de frais ou confirmer un paiement
sans réception attestée. Cette autorisation ne constitue pas une preuve de bon fonctionnement.

## État vérifié

- Branche de travail `work/covi-production-integration`, créée à partir de PR 28,
  commit `dbb35c9d583d43e7217fe43942ed9c998e617a8c`.
- PR 22 : `df2ce0dfd319783a920097f73a7008abbc72e23c`.
- PR 28 : workflow 38587936937, test-web et test-db réussis ; build-windows ignoré.
  Source : https://github.com/yarobkl/COVI/actions/runs/38587936937
- Historique Supabase relu : huit migrations caisse présentes, versions
  20261014144526 à 20261014145439. Ne pas les rejouer sous les horodatages du dépôt.
- Lecture du relais `docs/claude-work-caisse-securisee.md` terminée.
- Les branches divergent : PR 22 possède ses propres checkout_cashiers et un stock
  par catégories ; PR 28 utilise shop_members et les produits existants.
  Une fusion brute ne réalise pas le parcours unifié demandé.
- Le checkout local historique COVI/main contient des modifications non commitées :
  elles sont préservées dans leur répertoire. Travail dans COVI-integration.

## Publication et blocage

- Aucun changement de schéma ou de donnée de production dans cette reprise.
- Aucune fusion ou publication effectuée.
- Vercel, page des variables COVI : redirection vers Login dans le navigateur cloud.
  Une connexion personnelle est nécessaire pour reprendre les réglages web.
- La clé publique Turnstile fournie précédemment ne prouve pas la présence de sa
  clé secrète serveur. Vérifier sans révéler les valeurs.

## Prochaines actions exactes

1. Terminer la connexion Vercel, vérifier projet/équipe et configuration réelle.
2. Adapter la passerelle PR 22 aux membres/PIN et produits PR 28 ; conserver une
   seule transaction de vente et une seule source de stock. Ne pas importer un
   deuxième système de comptes caissiers.
3. Exécuter les contrôles de compatibilité et d'isolation avant toute migration.
   Les tests CI ci-dessus ne prouvent pas l'intégration QR, encore non réalisée.
4. Sauvegarder les corrections, publier les migrations additionnelles validées et
   la fonction Edge avec ses secrets, puis le frontend ; vérifier le site réel.
5. Fournir le QR uniquement après génération par COVI et vérification publique.
   Ne pas inventer de demande, de reçu ou de confirmation de paiement.
