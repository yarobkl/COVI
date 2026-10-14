# Décision produit COVI — Passage de caisse par PIN, sans déconnexion visible

**Décision explicite du propriétaire (14/10/2026)**

> « Suis pas obligé de me déconnecter pour passer en caisse mais par contre il faut impérativement un code oui. »

Cette décision **remplace le parcours “Passer la caisse → Déconnecter le responsable” actuellement publié**. Elle ne justifie pas de rétablir le précédent écran PIN seul, qui conservait un JWT propriétaire exploitable dans le navigateur.

## Parcours UX obligatoire

1. Le responsable est déjà connecté à la boutique.
2. Dans Vendre, il appuie sur **Changer de caissier** (pas « Déconnecter le responsable »).
3. Une liste montre les caissiers actifs avec PIN déjà initialisé.
4. Le caissier choisi saisit son **PIN personnel** ; le serveur vérifie le code (hachage, compteur d'échecs, verrouillage).
5. L'écran passe automatiquement en **mode caisse limité au caissier**, sans formulaire de login/mot de passe visible ni déconnexion apparente du responsable.
6. **Changer de caissier** exige le PIN du prochain employé, sans réutiliser l'autorisation du précédent.
7. **Revenir à l'espace responsable** exige impérativement le PIN personnel du responsable ; la vérification doit avoir lieu côté serveur, être journalisée et limitée en tentatives.
8. Le mode comptoir se verrouille après inactivité ; le PIN du caissier actif est requis pour reprendre.
9. Aucun changement de rôle ne doit perdre les ventes en attente de synchronisation ni dupliquer une vente.
10. Identités réelles, limites de remise, historiques et accès aux données doivent être vérifiés **côté backend**.

## Exigence de sécurité non négociable

**L'ancien modèle “session Supabase propriétaire + composant React masqué + PIN” est interdit.**

Le simple masquage d'écrans ne retire pas les droits du JWT `auth.uid()` du propriétaire : un caissier pourrait appeler directement des endpoints et des RPC. La PR #28 a actuellement résolu ce risque par une déconnexion, mais ce contournement UX n'est pas acceptable comme solution finale.

Concevoir une vraie séparation des capacités tout en gardant l'expérience sans déconnexion visible. Solution à étudier : BFF/serveur tenant la session privilégiée dans un contexte inaccessible au navigateur, et émettant après PIN un **contexte de caisse à privilèges minimaux**, borné à l'employé, à la boutique, à l'appareil, à la session et à une durée courte. Avant le passage en caisse, faire disparaître de l'environnement accessible au caissier tout jeton propriétaire exploitable ; ne jamais stocker un `service_role`, refresh token propriétaire ou secret serveur dans localStorage/sessionStorage, JS ou code public. Le retour propriétaire nécessite une preuve PIN validée côté serveur, en complément d'une session d'appareil authentifiée et correctement limitée en tentatives ; certaines actions sensibles peuvent demander une réauthentification renforcée.

Si un BFF ou une authentification à jetons séparés n'est pas réalisable immédiatement, garder le flux sûr actuel temporairement, **mais ne pas prétendre que le besoin produit est satisfait**.

Ne pas réactiver `open_till_session` sous JWT propriétaire sans preuve d'isolement technique. Avant production, tester avec navigateur DevTools/REST, JWT signés de vrais comptes, accès interdits aux données privées, échec PIN, concurrence et retour responsable.

## État au moment de cette décision

- Le code de la PR #28 et le front déployé sur `covi-snowy.vercel.app` demandent actuellement une déconnexion explicite.
- Huit migrations de la caisse ont été appliquées en production ; ne pas les rejouer.
- Les tests auto CI de la PR #28 sont verts sur `dbb35c9d583d43e7217fe43942ed9c998e617a8c` mais ne vérifient **pas** cette nouvelle UX sans déconnexion.
- Aucun code de cette nouvelle architecture n'est encore déployé. **Ne pas changer la production ni sacrifier la sécurité sans validation réelle.**

## Critères d'acceptation

Un test humain sur deux employés et un responsable doit prouver les 3 transitions **responsable → caissier A → caissier B → responsable** via PIN, **sans déconnexion ni saisie de mot de passe visible**, avec vérifications réseau prouvant l'absence de privilèges propriétaire pendant les sessions caissiers. Toute action propriétaire directe depuis la caisse doit échouer, même en modifiant le navigateur.

La fonctionnalité QR public client est distincte de la gestion d'appareil partagé : ne pas les confondre.
