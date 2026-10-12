# COVI — Suivi de finalisation QR / réseaux sociaux

Dernière mise à jour : 2026-10-12
Projet : `yarobkl/COVI`, PR #22, branche `feature/covi-stock-central-omnichannel`.

## Terminé et preuves

- PR #22 ouverte, brouillon, non fusionnée. Commit de suivi enregistré : `7b06165fb6fa9589479ce8e24f03e6043ada1f97`. Aucun merge.
- Vérifications déjà réussies sur `c5bac84cfa3a4c32f388ca62f4d6b947f4c6b297` :
  - [COVI Windows](https://github.com/yarobkl/COVI/actions/runs/38295190809) : format, lint, TypeScript, build et tests web réussis ; job natif Windows ignoré dans la PR.
  - [COVI isolated branch checks](https://github.com/yarobkl/COVI/actions/runs/38295190801) : unit/static et PostgreSQL jetable réussis.
  - [COVI native Supabase sandbox](https://github.com/yarobkl/COVI/actions/runs/38295190824) : Auth et PostgREST Supabase locaux jetables réussis, rôles/RLS, isolation des boutiques, commandes idempotentes, aucun stock décrémenté au dépôt.
- Sur le checkpoint `7b06165`, les trois workflows sont maintenant terminés avec succès : [contrôles isolés](https://github.com/yarobkl/COVI/actions/runs/38298381749), [COVI Windows](https://github.com/yarobkl/COVI/actions/runs/38298381774), [sandbox Supabase natif Auth/PostgREST](https://github.com/yarobkl/COVI/actions/runs/38298381764). Le build natif Windows reste ignoré selon la configuration de la PR.
- Vercel a produit un aperçu READY sur le checkpoint `8c30d87`. Ce build ne valide pas le parcours métier ; aucun test utilisateur distant n'a été réalisé.
- Runbook de passerelle : `docs/public-gateway-staging-runbook.md`. Il exige Turnstile, vérification serveur du hostname/action, secret serveur uniquement, quotas atomiques ; la fonction reste inactive sans configuration.
- Supabase `bmbwmwgfzrijglzcgjut` : `ACTIVE_HEALTHY`, Postgres 17. Aucune fonction Edge, branche de développement ou migration de caisse. Aucun changement au schéma de production.
- Cloudflare : le navigateur affiche la connexion. Aucune clé Turnstile créée, lue ou transmise.

## Modifications et commits de cette session

- Ajout puis mise à jour de ce journal sur la branche autorisée.
- Checkpoints : `8c30d8772e0a8e52c7b6ff2d9d182c98c11b4987`, `7b06165fb6fa9589479ce8e24f03e6043ada1f97`, puis journal actualisé `f6cfb96f775902973db939b0be533c7286def886`.
- Aucun code applicatif, secret, schéma Supabase, provider OAuth ou paramètre de production modifié.

## Tests

Réussis : format/lint/TypeScript/build/tests web, tests unitaires/statique, PostgreSQL jetable et Auth/PostgREST Supabase local sur les runs cités, y compris les trois workflows du checkpoint `7b06165`.
Non exercés en conditions réelles : challenge Turnstile réel, fonction Edge distante, Supabase distant isolé, QR/WhatsApp sur smartphone, confirmation manuelle du paiement puis stock/historique/statistiques.
Installateur natif Windows ignoré par le workflow de PR.
Aucun test n'a écrit dans la base de production.

## Blocages

1. Session Cloudflare absente : créer un widget requiert une authentification personnelle.
2. Aucun Supabase distant isolé n'existe. Le seul projet connu est la production ; ne pas y déployer la fonction ni les SQL de caisse. Ne créer aucun projet ou branche payante.
3. Passerelle Edge et secrets serveur non déployés/configurés.
4. Pas de preuve E2E distante du parcours QR/social → commande → approbation → confirmation paiement → stock → historique.
5. La PR reste brouillon et l'audit de PR mentionne encore des blocages comptables, de statistiques, de vie privée, d'accès caissiers et de tests mobile. **NO-GO production.**

## Prochaine action exacte

1. L'utilisateur connecte le compte Cloudflare dans le navigateur sécurisé.
2. Vérifier la disponibilité du widget gratuit et d'un domaine de test ; créer le widget en conservant la clé secrète uniquement côté serveur.
3. Utiliser ou préparer un staging Supabase strictement isolé et gratuit. Si indisponible, s'arrêter sans toucher à la production.
4. Déployer fonction et secrets uniquement en staging ; tester le parcours QR/WhatsApp, approbation, paiement manuel, stock et historique ; consigner le résultat. Toute activation publique en production reste soumise à validation explicite.
