# Revue de divergences — COVI (22 octobre 2026)

> Analyse GitHub en lecture seule des branches contre `main`. Cette revue ne vaut pas validation de fusion. Aucun test local ni déploiement effectué.

## Comparaisons GitHub

| Branche | État | Ahead | Behind | Interprétation |
|---|---|---:|---:|---|
| `feature/api-stock-realtime-20261019` | diverged | 16 | 5 | Prévoir revue fine des migrations et Edge : PR #54 déjà fusionnée |
| `feature/covi-connect-websites-20261019` | diverged | 30 | 4 | Prévoir revue fine du gateway et des commandes : PR #55 déjà fusionnée |
| `feature/covi-geo-intelligence-foundation` | diverged | 1 | 227 | Unique fichier documentaire `docs/roadmap/COVI_GEO_INTELLIGENCE_V2.md` dans la comparaison ; ne pas l'assimiler à une feature prête |
| `chatgpt/saas-subscription-architecture` | diverged | 18 | 236 | Anciennes migrations et composants admin ; incompatibilités probables avec l'évolution des schémas |
| `feature/covi-restaurant-salon-v1` | diverged | 289 | 14 | Branche substantielle, plusieurs docs/migrations/tests ; PR #52/#53 ont déjà intégré une partie |

### Conséquences opérationnelles

- Les nombres ahead/behind décrivent l'histoire git, **pas** les fonctionnalités nettes manquantes.
- Ne pas faire `git merge` ou `cherry-pick` de ces branches sans comparer les patches individuels et le schéma actuel.
- PR #54 et #55 déjà fusionnées : tout travail supplémentaire sur ces branches doit se justifier par un écart précis à `main`.
- La branche géointelligence n'apporte actuellement qu'un document dans cette comparaison ; elle est utile pour la stratégie, pas pour l'intégration directe.
- La branche abonnement accuse plus de 200 commits de retard : **ne jamais appliquer ses migrations telles quelles** sans audit de schéma et test de migration sur base jetable.

## Contrôles de code établis

- `src/app/routes.ts` contient les routes commerciales, restaurant, salon et assistant.
- `src/features/assistant/AssistantPage.tsx` conserve les derniers échanges localement dans la page, jusqu'à six échanges transmis comme contexte pour la requête. Le backend doit continuer à rejeter tout contexte malveillant et vérifier la boutique.
- `src/lib/covi.ts` utilise `rpc('record_sale')` pour enregistrer les ventes.
- `src/lib/operations.ts` effectue certains calculs journaliers et mensuels en JavaScript avec le fuseau du navigateur. Vérifier les différences avec les agrégats SQL localisés, particulièrement pour les dates à minuit.
- `supabase/config.toml` définit plusieurs Edge Functions publiques avec `verify_jwt=false` ; les garanties doivent être vérifiées *dans chaque handler*, sans conclure à une faille de sécurité à partir de la configuration seule.
- `.github/workflows/windows.yml` prévoit format, lint, types, build, tests Node/Vitest et SQL PostgreSQL 16.

## Prochaine intervention de code recommandée : P0

1. Lire les définitions et tests des RPC `record_sale`, `record_cart_sale`, `adjust_product_stock`, COVI Connect et de l'assistant.
2. Établir les contrats du schéma/roles de `main` et les comparer aux dernières migrations de chaque branche.
3. Ajouter des tests ciblés de non-régression si les tests actuels sont insuffisants ; faire échouer la CI avant de changer une règle métier.
4. Corriger uniquement les défauts reproductibles, dans des PR distinctes.
5. Démarrer le CRM sur une migration additive distincte, activable indépendamment et désactivée par défaut si elle touche le front.

## Interdictions tant que la revue n'est pas terminée

- Aucun merge direct de branche ancienne.
- Aucune modification `main`, donnée Supabase, variable d'environnement ou déploiement Vercel.
- Aucun accès `service_role` côté client, aucune mutation de ventes depuis Gemini.
- Aucune prétention de tests « réussis » tant que leur exécution n'est pas attestée.

## Traçabilité

Source : compare commits GitHub `main...<branche>`, récupéré le 22 octobre 2026. Voir PR #59 pour le plan général. Tout changement de code ultérieur nécessitera CI et validation séparées.
