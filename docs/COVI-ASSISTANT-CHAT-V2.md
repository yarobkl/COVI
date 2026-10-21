# COVI Assistant IA — conversation continue (V2)

## Quoi de neuf ?

- Interface de **chat** mobile : bulles utilisateur/assistant, composition en bas,
  validation Entrée, Maj+Entrée pour un retour à la ligne, bouton « Nouvelle conversation ».
- **Mémoire contextuelle éphémère** : les 6 derniers échanges réussis (max. 12 messages)
  sont retransmis à Gemini. Pas de base de données ni de stockage local de discussions ;
  un rechargement ou une navigation hors de la page réinitialise la conversation.
- L'utilisateur accepte explicitement l'envoi de ses messages à Google Gemini.
- Le PIN responsable reste au maximum 10 minutes dans l'état volatile de la page
  (jamais sauvegardé), puis doit être ressaisi. Il est **recontrôlé côté serveur
  à chaque message** ; les sessions caisse partagées ne donnent pas directement
  accès aux indicateurs du responsable.
- Quota augmenté de **12 à 60 messages par heure UTC et par boutique**, avec SQL
  transactionnel atomique en cas de concurrence. Il s'agit d'un plafond COVI,
  indépendant des limites de Google ; des coûts et autres limites Gemini restent possibles.

## Sécurité & justesse

- Aucun des messages d'historique n'est considéré comme une source de données
  financière fiable. À chaque réponse, le serveur transmet les seuls indicateurs
  à jour et contrôlés sous la session du propriétaire.
- Historique entré par le client soumis à un schéma strict : alternance user/model,
  6 paires au maximum, longueur bornée, aucun rôle system/tool recevable.
- Aucune donnée d'autre boutique n'est consultée ; aucun secret Gemini ni PIN
  n'est envoyé au modèle. Les ventes/paiements/stocks restent en lecture seule.
- Limitation de la taille des requêtes HTTP à 18 000 caractères, des questions
  à 600 et des sorties Gemini à 850 tokens environ (et 5 000 caractères
  retournés au navigateur). Une requête Gemini réussie compte pour un message.
  Le quota est consommé avant l'appel, même si Google ne répond pas.
- Pour les salons/restaurants : conseils métier généraux, pas de faux indicateurs.
  Pour les boutiques : **ventes moins charges ≠ bénéfice net**.
- Si un commerçant souhaite garder des conversations entre appareils, la
  persistance nécessitera ultérieurement un système distinct de permissions
  et de conservation, et un consentement adapté.

## Activation

1. Tester la migration `20261021193000_covi_ai_chat_hourly_quota.sql` sur
   base isolée avec toute la suite SQL, vérifier la contrainte `used <= 60`.
2. Déployer la migration via Supabase ; l'ancienne limite reste tant que ce
   n'est pas fait.
3. Déployer le nouveau `covi-assistant` (handler et index) avec JWT obligatoire,
   sans afficher ni modifier `GEMINI_API_KEY`.
4. Fusionner la PR et publier le front Vercel, vérifier domaine `covi-snowy.vercel.app`.
5. Test manuel connecté : deux messages consécutifs et suivi contextuel,
   puis « Nouvelle conversation » ; PIN refusé si erroné ; conserver la
   possibilité `COVI_AI_ENABLED=false` pour arrêter les appels.

## Tests

- `npm test`, `npm run lint`, `npm run typecheck`, `npm run format:check`
- `tests/sql/run.sh --tmp-cluster`
