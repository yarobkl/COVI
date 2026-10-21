# COVI Assistant IA — préparation, non déployée

## Objectif

Page `#/assistant` dans les trois métiers : boutique, restaurant et salon.
Le texte généré par Google Gemini est un **conseil**. L'IA ne peut ni écrire en base,
ni créer une vente, ni modifier le stock, ni confirmer un paiement.

## Sécurité et données

- Edge Function `covi-assistant` avec `verify_jwt = true`.
- Contrôle de session via Supabase Auth **et** vérification du propriétaire de
  l'établissement avec son JWT (RLS). **Aucune clé service_role** utilisée.
- Quota atomique SQL de 12 questions par établissement et heure UTC ;
  refus fermé si RPC absente ou indisponible. Les lignes de quota restent
  en base : prévoir une purge des anciennes fenêtres avant exploitation à grande échelle.
- Pas de clé Gemini dans Vite, React, localStorage, GitHub ou la réponse réseau.
- Consentement de l'utilisateur avant chaque session de la page ; la question et
  un sous-ensemble des données sont envoyés à Google Gemini. Vérifier les
  conditions de traitement, de rétention et la politique de confidentialité
  selon le contrat Gemini/Google choisi avant activation publique.
- Aucune donnée nominative de clients, coordonnées, jetons, PIN, commandes
  détaillées, ou textes d'opérations n'est transmise intentionnellement.
  L'utilisateur est invité à ne pas écrire de données personnelles dans sa question.
- Les conversations ne sont pas persistées côté COVI. L'API Google reçoit
  néanmoins les données nécessaires au traitement selon ses propres conditions.
- **Attention caisse partagée :** le JWT propriétaire peut être utilisé sur un
  terminal partagé. Avant mise en production, contrôler le cloisonnement
  serveur du mode PIN ou interdire l'assistant depuis une session caisse partagée.
  L'interface ne constitue pas une garantie d'autorisation.

## Métriques de la V1

**Boutique seulement :** lecture du résultat existant `shop_dashboard` et
de 10 alertes stock, après validation du propriétaire. Pas de réécriture de
formules financières. Données de test exclues ; ventes hors ligne non synchronisées
non incluses. `restAfterCharges` n'est pas un bénéfice net, les coûts des ventes
et charges manquantes peuvent rendre cette valeur non représentative.
Le fuseau du pays reste à résoudre : XAF utilise Africa/Brazzaville, les
autres devises utilisent UTC, avec fuseau explicite dans le contexte.

**Restaurant et salon :** recommandations générales uniquement pour l'instant,
sans chiffres de ventes, résultats, réservations ou encaissements. Éviter
de présenter ces fonctions comme un tableau de bord IA déjà branché.

## Activation (préproduction d'abord)

1. Tester les migrations dont `20261021180000_covi_ai_hourly_quota.sql`
   dans une base isolée, puis les contrôles RLS et le quota concurrent.
2. Créer une clé dans [Google AI Studio](https://aistudio.google.com/apikey).
   **Ne pas partager sa valeur par chat** ; la renseigner dans les secrets Edge
   Supabase : `GEMINI_API_KEY`. Coûts éventuels facturés par Google.
3. Définir `COVI_AI_ENABLED=true` et
   `COVI_AI_ALLOWED_ORIGINS=https://covi-snowy.vercel.app`
   dans les secrets Edge ; modèle `GEMINI_MODEL` facultatif, par défaut
   `gemini-2.5-flash`.
4. Vérifier que `SUPABASE_URL` et `SUPABASE_ANON_KEY` sont disponibles.
   Tester l'appel avec un propriétaire et avec un utilisateur sans droit.
5. Revoir le périmètre des informations sensibles, quotas, traçage des coûts,
   conditions contractuelles Google, et test mobile réel.
6. **Après accord explicite**, appliquer la migration, déployer la fonction Edge,
   puis publier le frontend. Pas de déploiement automatique ni de clés en clair.

## Tests

- `node --test tests/covi-assistant-handler.test.mjs`
- `npm test`, `npm run typecheck`, `npm run lint`, `npm run format:check`
- SQL : `tests/sql/run.sh --tmp-cluster` sur base éphémère seulement.

Une réponse Gemini peut se tromper même quand les indicateurs de source sont corrects.
La validation des décisions financières reste au commerçant.
