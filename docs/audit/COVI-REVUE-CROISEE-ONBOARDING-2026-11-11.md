# COVI — revue croisée des sept spécialités — 11 novembre 2026

## Portée
Branche isolée `audit/covi-seven-roles-2026-11`. Aucun déploiement, aucune modification Supabase, aucun TestFlight.

## Alexandre — Produit
- Accueil : Commencer -> inscription ; Se connecter -> connexion.
- Compte existant : la session Supabase ouvre l'établissement propriétaire ou l'espace employé existant.
- Nouveau compte sans établissement : `CreateShopForm` assure ensuite l'identité du propriétaire, le métier et la localisation.
- Le retour vers connexion est disponible depuis l'inscription.

## Sarah — UX/UI
- Palette beige, bleu marine et composants de dimensions communes dans la couche CSS iOS.
- Même marque COVI Commerce & Vie sur accueil, connexion et inscription.
- Accueil sans faux points de pagination, avec aperçu illustratif.
- À confirmer sur captures réelles : disposition petits iPhone, clavier ouvert, boutons au-dessus du clavier.

## Kevin — iOS
- `type=email`, `autoComplete=email`, `current-password` et `new-password` existent dans les champs.
- `PhoneInput` utilise `type=tel`, `inputMode=numeric` et `autoComplete=tel-national`.
- Safe areas iOS et `prefers-reduced-motion` sont pris en compte.
- Les suggestions iOS dépendent des réglages et des données sauvegardées sur l'appareil, elles ne sont pas garanties.
- Blocage de validation : le retour OAuth Google dans Capacitor doit être vérifié sur appareil. Le code actuel emploie `signInWithOAuth` et une URL web, sans preuve de retour de session natif.

## Amina — Supabase
- `AuthGate` consulte les commerces propriétaires et les appartenances caissier/restaurant/salon.
- La création e-mail iOS ne demande plus les détails du commerce avant l'inscription ; ils sont recueillis après.
- La confirmation e-mail dépend de la configuration réelle de Supabase, non vérifiée.
- Aucun schéma ni politique RLS modifié.

## David — Sécurité
- Pas de requête permettant d'énumérer publiquement les adresses enregistrées.
- Ne pas supposer qu'un même e-mail Google/Apple fusionne automatiquement les identités.
- La liaison des comptes et les redirections OAuth restent à auditer avant diffusion.

## Chloé — QA
Scénarios nécessaires sur simulateur ou iPhone : accueil -> inscription -> retour -> connexion ; saisie e-mail et mot de passe ; erreurs ; confirmation e-mail ; Apple ; Google ; utilisateur propriétaire existant ; nouvel utilisateur ; employé invité ; rotation et clavier ouvert ; retour après interruption.
**Aucun de ces tests n'a été exécuté sur iPhone dans cette session.**

## Samuel — DevOps
- Modifications confinées à la branche d'audit.
- Aucun workflow TestFlight déclenché.
- Compilation TypeScript, lint, tests et build iOS restent à exécuter dans un environnement de build autorisé.

## Conclusion
Travail de revue par spécialités, **pas sept agents autonomes ayant exécuté des tests**. Ne pas fusionner ni envoyer sur TestFlight avant compilation et vérification du parcours OAuth sur iOS.
