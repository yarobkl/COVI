# COVI — Suivi de finalisation QR / réseaux sociaux

Dernière mise à jour : 2026-10-12
Projet : `yarobkl/COVI`, PR #22, branche `feature/covi-stock-central-omnichannel`.

## Terminé et preuves

- PR #22 reste ouverte, en brouillon, non fusionnée. HEAD contrôlé : `8c30d8772e0a8e52c7b6ff2d9d182c98c11b4987`. Aucun merge effectué.
- Vérifications antérieures réussies sur `c5bac84cfa3a4c32f388ca62f4d6b947f4c6b297` :
  - [COVI Windows](https://github.com/yarobkl/COVI/actions/runs/38295190809) : format, lint, TypeScript, build et tests web réussis ; job natif Windows ignoré dans la PR.
  - [COVI isolated branch checks](https://github.com/yarobkl/COVI/actions/runs/38295190801) : unit/static et PostgreSQL jetable réussis.
  - [COVI native Supabase sandbox](https://github.com/yarobkl/COVI/actions/runs/38295190824) : Auth et PostgREST Supabase locaux jetables réussis, rôles/RLS, isolation des boutiques, commandes idempotentes, aucun stock décrémenté au dépôt.
- Au HEAD `8c30d87`, la dernière lecture Actions indique : contrôles isolés réussis ; workflow COVI Windows et sandbox Supabase encore en cours au moment de la vérification. [État des actions](https://github.com/yarobkl/COVI/actions).
- Vercel a produit un aperçu `READY` pour le HEAD `8c30d87`. Le build vert ne valide pas à lui seul le parcours métier. Aucun lien de prévisualisation n'est publié ici.
- Runbook de la passerelle : `docs/public-gateway-staging-runbook.md`. Il prévoit Turnstile requis, vérification serveur du hostname/action, secret côté serveur uniquement, quotas atomiques et fonction inactive avant configuration.
- Supabase `bmbwmwgfzrijglzcgjut` est `ACTIVE_HEALTHY` (Postgres 17), mais ne contient aucune fonction Edge, branche de développement ni migration de caisse. Aucun schéma de production n'a été modifié.
- Cloudflare : le navigateur disponible affiche la connexion. Aucune clé Turnstile n'a été créée, lue ou transmise.

## Modifications et commits de cette session

- Ajout de ce journal au dépôt sur la branche autorisée.
- Commit checkpoint : `8c30d8772e0a8e52c7b6ff2d9d182c98c11b4987`.
- Aucun code applicatif, secret, schéma Supabase, provider OAuth ou configuration de production modifié.

## Tests

Réussis : web format/lint/TypeScript/build/tests, tests unitaires/statique, PostgreSQL jetable et Auth/PostgREST Supabase local sur les commits listés ci-dessus.
En cours lors du dernier relevé pour le HEAD actuel : workflow web Windows et sandbox Supabase.
Non exercés en conditions réelles : vrai challenge Turnstile, fonction Edge distante, environnement Supabase isolé, parcours QR/WhatsApp complet sur smartphone, confirmation de paiement puis stock/historique/statistiques.
L'installateur Windows natif est ignoré dans le workflow de PR.
Aucun test n'a écrit dans la base de production.

## Blocages

1. Session Cloudflare absente dans le navigateur : impossible de créer une clé Turnstile sans authentification personnelle.
2. Aucun environnement Supabase distant isolé n'existe. Le seul projet connu est la production ; ne pas y déployer la fonction ni les SQL de caisse. Aucun projet ou branche payante ne doit être créé.
3. La passerelle Edge n'est pas déployée et ses secrets serveur ne sont pas configurés.
4. Il n'existe donc pas encore de preuve E2E distante pour le parcours QR/social → approbation → confirmation manuelle du paiement → stock → historique.
5. La PR demeure en brouillon et contient encore les blocages comptables/sécurité/statistiques listés dans son audit. Verdict : NO-GO production.

## Prochaine action exacte

1. L'utilisateur connecte le compte Cloudflare dans le navigateur sécurisé disponible.
2. Vérifier que l'offre Turnstile gratuite et un domaine de test sont disponibles ; créer le widget et conserver sa clé secrète hors chat, dépôt, logs et navigateur client.
3. Utiliser ou préparer un environnement Supabase de staging strictement isolé et gratuit. Si aucun n'est disponible, s'arrêter sans toucher à la production.
4. Déployer passerelle et secrets uniquement en staging ; exécuter le parcours E2E QR/WhatsApp, paiement manuel, stock et historique ; consigner les résultats et garder l'activation publique de production en attente de validation explicite.
