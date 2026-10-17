# COVI — Mission bloquante : caisse sans déconnexion visible, PIN obligatoire

**Décision du propriétaire** : même appareil, responsable → caissier A → caissier B → responsable, uniquement par PIN personnel, sans formulaire de connexion, mot de passe ou déconnexion **visible**. La sécurité doit être imposée au serveur, pas simplement à React.

## État vérifié le 14 octobre 2026

- Production officielle : `https://covi-snowy.vercel.app`. Actuellement « Passer la caisse » déconnecte le propriétaire. **Ce comportement n'a pas été corrigé.**
- GitHub `yarobkl/COVI`, branche `claude/caisse-multi-caissiers`, PR #28. 8 migrations multi-caissiers déjà installées en Supabase prod `bmbwmwgfzrijglzcgjut` (ne pas rejouer).
- Les PIN propriétaire/caissier et les limites de remises côté SQL existent.
- Prototype exploratoire : `docs/experimental/counter_session_rls_prototype.sql` (**INTERDIT de déployer tel quel**). Test SQL a relevé des régressions ; les essais réels JWT ne sont pas passés. Cet essai de RLS ne suffit pas : garder un JWT propriétaire dans le navigateur permet de viser les endpoints Supabase Auth même si les tables sont verrouillées par RLS.
- Le prototype a volontairement été retiré de `supabase/migrations/` ; aucune modification auth SQL de cette mission n'a été appliquée à la production.

## Implémentation attendue

1. **Concevoir un vrai serveur de sessions d'appareil partagé** (BFF / Edge Function) qui conserve les droits du propriétaire hors de portée du navigateur du caissier : coffre serveur et cookie opaque HttpOnly/Secure/SameSite sur le domaine COVI, rotation et invalidation. Ne jamais exposer `service_role`, l'access token ni le refresh token propriétaire au JavaScript pendant le mode caisse.
2. Exiger une vérification PIN **côté serveur** à chaque transition de caissier, appliquer un verrouillage après erreurs, et créer un contexte d'autorisation spécifique au caissier (identité distincte, boutique, remise maximale, session, délai d'inactivité). La caisse est limitée au stock vendable et à ses ventes. Aucun accès aux charges, arrivages, marges, paramètres, invitation ou aux secrets de l'entreprise.
3. Le retour responsable doit vérifier son PIN côté serveur, invalider immédiatement la délégation et rétablir ses droits sans qu'il ait à saisir son mot de passe. Prévoir une récupération plus forte (réauthentification complète) si PIN perdu.
4. Remplacer le bouton actuel par « Changer de caissier » et un sélecteur d'employés suivi du pavé PIN. Pas d'écran « Déconnecter le responsable ». Les ventes non synchronisées doivent bloquer toute bascule dangereuse.
5. **Sécurité à prouver** : tests E2E avec vrais JWT signés, tentatives REST/RPC et Supabase Auth direct, manipulation devtools, rechargement, onglet séparé, fermeture navigateur, refresh token, code PIN erroné, concurrent cashiers, remises, stock et profil propriétaire. Une simple couche RLS/JS n'est pas suffisante.
6. Tester en environnement **isolé**, utilisateurs fictifs et vrais appareils/navigateurs, zéro vente réelle. Corriger lint/typecheck/vitest/test-db jusqu'à CI verte. Donner captures réelles, preuves de restrictions serveur et mesure des transitions.
7. **Garde-fous** : ne pas modifier 150 ventes/55 produits/3 boutiques existants, ne pas activer d'abonnement payant, ne pas fusionner la PR #28 ni déployer sur le domaine officiel tant que les tests sécurisés ne sont pas passés. Aucun rollback de production sans accord.

### Critères d'acceptation

Sur un même iPhone : connecté responsable → « Changer de caissier » → choisir A → PIN A → vente attribuée à A → choisir B → PIN B → vente attribuée à B → « Revenir au responsable » → PIN du propriétaire → tableau de bord ; aucun login ni déconnexion visible. Pendant les deux caisses, aucun appel API détourné ne peut récupérer les droits du responsable, y compris endpoints Auth. Publication uniquement après preuves et accord explicite.

**Priorité P0.** Ne pas détourner vers les QR clients ou les menus déroulants.
