# COVI Assistant — sans code PIN dans le chat

Le propriétaire connecté peut envoyer ses messages à Gemini sans saisir de PIN
responsable. Cette évolution est limitée **au chatbot** : elle ne supprime pas
les codes PIN de caisse ni le contrôle de sortie du mode comptoir.

## Sécurité et sessions
- JWT Supabase valide, session propriétaire de la boutique vérifiée deux fois
  (Edge et RPC SQL dédiée), session_id du JWT obligatoire.
- Le serveur refuse le chatbot si un magasin a une session de caisse partagée
  active **sur le même session_id** (pour les deux mécanismes de caissiers COVI).
- Les anciennes sessions sans session_id sont traitées comme inconnues : tant
  qu'elles sont actives, le chatbot est temporairement inaccessible à la
  boutique, par sécurité. Réouvrir la caisse après la migration permet de
  rattacher les nouvelles sessions à leur appareil.
- Les tests comprennent : appareil personnel autorisé, deux types de caisse
  partagée refusés, autre session autorisée, anciennes sessions indéterminées
  bloquées, utilisateurs non propriétaires refusés, sessions JWT sans identifiant
  refusées.
- Cette protection est spécifique au chatbot : elle ne rend pas sûre, à elle
  seule, une session propriétaire partagée. Pour un accès sensible sans code,
  préférer un téléphone personnel.
- Aucune écriture dans les ventes, stocks, commandes ou paiements, aucun
  changement des PIN collaborateurs existants.

## Publication
1. Tester en CI (format, lint, compilation, JS/TS, SQL complet).
2. Appliquer la migration 20261021194500_covi_ai_owner_session_guard.sql.
3. Vérifier covi_ai_owner_session_allowed et les triggers.
4. Déployer supabase/functions/covi-assistant avec verify_jwt=true.
5. Fusionner la PR et déployer Vercel vers covi-snowy.vercel.app.
6. Tester sur une session propriétaire (sans PIN) et une vraie caisse partagée.

**Si le contrôle serveur manque ou échoue, l'assistant se ferme** plutôt
que de diffuser des données à une session non autorisée.
Le quota de 60 messages/heure reste en place.
