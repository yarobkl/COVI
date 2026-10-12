# COVI — Suivi de finalisation QR / réseaux sociaux

Dernière mise à jour : 2026-10-12 21:17 Europe/Paris
Projet concerné : `yarobkl/COVI`, PR #22, branche `feature/covi-stock-central-omnichannel`.

## Terminé et preuves

- PR #22 vérifiée : ouverte, brouillon, non fusionnée, base `main`. Aucun merge effectué.
- Contrôles GitHub associés au commit PR `c5bac84cfa3a4c32f388ca62f4d6b947f4c6b297` :
  - [COVI Windows](https://github.com/yarobkl/COVI/actions/runs/38295190809) : succès pour format, lint, TypeScript, build et tests web ; build natif Windows ignoré selon la configuration de la PR.
  - [COVI isolated branch checks](https://github.com/yarobkl/COVI/actions/runs/38295190801) : succès pour tests unitaires/statique et test PostgreSQL jetable.
  - [COVI native Supabase sandbox](https://github.com/yarobkl/COVI/actions/runs/38295190824) : succès pour Auth et PostgREST Supabase locaux jetables, rôles, isolation propriétaire, création idempotente de commandes et absence de décrément de stock au dépôt.
- Le runbook `docs/public-gateway-staging-runbook.md` confirme : Turnstile obligatoire, vérification serveur, secret serveur uniquement, quotas atomiques et passerelle inactive jusqu’à configuration.
- Projet Supabase `bmbwmwgfzrijglzcgjut` : `ACTIVE_HEALTHY`, Postgres 17. Liste actuelle des fonctions Edge vide ; branches de développement vides ; migrations enregistrées seulement jusqu’au socle existant du 7 octobre. Aucun schéma de caisse n’a été ajouté en production.
- Déploiements Vercel consultés pour cette branche : des aperçus `READY` existent, dont le commit `d051a40027c82cafe2340ae624e103b6e9539c28` (cible preview). La PR renvoyée par le connecteur indique encore `c5bac84` comme HEAD ; cet écart entre les deux vues doit être résolu avant une livraison.
- La limite Vercel gratuite de déploiements journaliers est atteinte : le commentaire Vercel dans la PR rapporte `api-deployments-free-per-day`, réessayer après 24 h. Aucun passage en offre payante.
- Cloudflare : la session de navigateur disponible affiche la page de connexion. Aucune clé Turnstile créée, lue ou transmise.

## Modifications et commits de cette session

- Aucun fichier applicatif modifié.
- Aucun commit ou push applicatif réalisé pendant cette vérification. Ce journal est le premier checkpoint demandé pour cette reprise.

## Tests

Réussis sur le commit `c5bac84...` : GitHub Windows web, contrôles isolés unitaires/statique, PostgreSQL temporaire, Supabase Auth/PostgREST local.
Non testés en conditions réelles : Turnstile Cloudflare, fonction Edge déployée, Supabase distant isolé, parcours smartphone/WhatsApp complet et affichage réel des ventes/statistiques.
Installateur Windows natif : ignoré par le workflow de PR.
Aucun test ayant écrit dans la base de production.

## Éléments bloquants

1. Cloudflare n’est pas connecté dans le navigateur disponible, donc impossible de créer les clés sans interaction de compte.
2. Aucun environnement Supabase isolé existant : créer un projet ou une branche peut entraîner un coût et est explicitement exclu sans validation. Ne pas déployer les brouillons SQL dans Supabase production.
3. Pas de fonction `public-checkout` Edge déployée ni secrets serveur configurés.
4. Le parcours complet QR/WhatsApp → commande → approbation → confirmation manuelle → stock → historique n’a pas été exercé sur un environnement Supabase distant isolé.
5. La limite de déploiements gratuits Vercel bloque de nouveaux builds pendant environ 24 h.
6. Confirmer le HEAD courant de la branche : PR snapshot `c5bac84...`, alors qu’un aperçu de cette même branche est lié à `d051a400...`.

## Prochaine action exacte

À la reprise, actualiser le HEAD/CI de la PR #22. Puis, après accès Cloudflare autorisé, créer un widget Turnstile gratuit limité au domaine exact de test et acheminer la clé privée directement vers les secrets de la fonction Supabase de staging — sans l’afficher dans le navigateur, GitHub ou le chat. Tant qu’aucun environnement isolé gratuit n’existe, maintenir la passerelle désactivée et laisser le verdict **NO-GO production**.
