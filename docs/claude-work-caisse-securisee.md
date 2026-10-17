# COVI — Passage à Claude / ChatGPT Work : caisse sécurisée

> **IMPORTANT — CHANGEMENT DE DÉCISION PRODUIT DU 14/10/2026 :** le propriétaire ne veut **PAS** être obligé de se déconnecter pour passer la caisse. Le basculement responsable → caissier → caissier → responsable doit se faire **par PIN impératif, sans déconnexion visible**, et avec une isolation réelle des privilèges côté serveur (pas un simple overlay React). Voir [décision produit PIN sans déconnexion](./decision-produit-passage-caisse-pin-sans-deconnexion.md). Le parcours actuel par déconnexion est seulement un repli sûr temporaire, **pas la fonctionnalité finale demandée**. Ne pas rétablir le JWT propriétaire dans le navigateur du caissier.

Dernière vérification : 14 octobre 2026. **Lire les données réelles et le CI courant avant toute action.**
Ce document est un relais exécutable, pas une autorisation de déployer.

## Contexte concret

- Dépôt GitHub `yarobkl/COVI`, branche `claude/caisse-multi-caissiers`, PR #28 : https://github.com/yarobkl/COVI/pull/28
- Production Vercel : `https://covi-snowy.vercel.app`, projet `covi` de `yarobkls-projects`.
- Supabase production : `bmbwmwgfzrijglzcgjut`.
- **Les 8 migrations de la PR #28 ont déjà été appliquées en production le 14/10/2026** via Supabase MCP, en ordre, avec vérification d'historique. Ne pas les rejouer.
- Derniers comptages SQL observés : **149 ventes, 55 produits, 3 boutiques, 0 membres caissiers, 0 PIN caissier, 0 invitations et 0 sessions comptoir.** Aucune donnée à inventer ou supprimer.
- Le front officiel reste sur `main` (SHA `ffbc1c73f1acf01fa801094827ff1da13a615ef2`), **pas** sur la PR #28.
- Projet gratuit de préférence : ne pas acheter d'option ou basculer de plan sans consentement explicite.
- PR #22 QR/social est séparée ; ne pas la mélanger à ce chantier.

## Correctif réalisé sur la branche, pas encore publié

La caisse de l'ancien « mode comptoir » s'ouvrait sous le JWT Supabase du propriétaire :
un code PIN et des écrans masqués ne peuvent pas restreindre les privilèges du propriétaire.
**Il faut éviter toute délégation à un employé tant que ce JWT est présent.**

Changements réalisés dans la PR #28 :

1. `src/features/team/TillSwitch.tsx` : remplace « Changer de caissier » sous JWT propriétaire par « Passer la caisse ». Le propriétaire se déconnecte, puis le caissier se connecte avec son propre compte et PIN. Refuse le transfert si ventes en attente de synchronisation.
2. `src/features/sale/SalePage.tsx` et `src/app/App.tsx` : transmettent la fonction de déconnexion du véritable AuthGate, pas une simple bascule UI.
3. `src/features/team/CounterGate.tsx` : retire les anciennes caisses de la navigation. Un mode comptoir ancien force la sortie du compte propriétaire lorsque la file hors ligne est vide ; aucune page propriétaire n'est montée.
4. `src/features/auth/AuthGate.tsx` : ne considère plus une déconnexion Supabase échouée comme réussie.
5. `src/features/team/TeamPanel.tsx` : retire la configuration de PIN responsable ambiguë ; conserve la gestion des membres, invitations, remises, réinitialisations de PIN individuels.
6. Tests `TillSwitch.test.tsx` et `CounterApp.test.tsx` : transfert, déconnexion, anciennes sessions et attente de synchronisation.

**Attention** : les RPC `open_till_session`, `leave_counter_mode` et `reset_owner_pin` restent en base pour compatibilité historique, mais le nouveau front ne doit plus les utiliser pour donner la caisse à un caissier. Ne pas modifier/retirer des RPC en production dans cette mission sans plan de compatibilité et autorisation.

## Audit SQL effectué (lecture seule)

- RLS activé sur tables de membres, PIN, invitations, audit et sessions.
- `anon` : aucun accès direct SELECT aux huit tables privées contrôlées.
- `authenticated` : aucun accès INSERT/UPDATE/DELETE direct à ces tables ; SELECT direct limité à `shop_members` et `shop_audit_log`, sous leurs politiques.
- Fonctions internes `cashier_pin_unlocked`, `cashier_touch_unlock`, `cashier_session_id` : pas de droit EXECUTE direct `anon`/`authenticated`.
- `record_sale`, `record_cart_sale`, `verify_my_pin` : RPC SECURITY DEFINER utilisables par des comptes authentifiés, avec contrôles internes d'autorisation à vérifier en conditions réelles.
- Conseiller Supabase : 24 fonctions SECURITY DEFINER exposées à authenticated (un examen des gardes internes est requis), 6 tables privées RLS sans politique (délibéré si aucun accès direct), protection des mots de passe compromis désactivée (ancien avertissement).

## Missions suivantes pour Claude / Work (ordre strict)

1. **Vérifier l'état actuel** : SHA de branche, PR, jobs `test-web` et `test-db`. Corriger échecs de Prettier/lint/TypeScript/Vitest, sans modifier `main`. Toute correction doit faire repasser le CI complet.
2. **Tester le parcours réellement sécurisé** : appareil A propriétaire > Vendre > Passer la caisse > déconnexion effective et invalidation locale du token propriétaire > page login > compte distinct employé > activation puis saisie PIN > vente test, nom du caissier > retour propriétaire seulement via connexion authentifiée.
3. **Tests d'accès hostiles (isolation authentifiée)** : caissier ne peut pas lire charges/bénéfices, voir d'autres boutiques, réinitialiser PIN du propriétaire, inviter des collègues, contourner PIN en appelant directement les RPC ou dépasser la remise. Vérifier RLS et `auth.uid()` avec de vrais JWT signés (pas seulement `set_config('request.jwt.claims')` en PostgreSQL).
4. **Tester les erreurs** : PIN incorrect/verrouillage, PIN réinitialisé, suppression membre, JWT expiré, échec déconnexion, trois navigateurs, refresh, deux comptes successifs, sessionStorage/localStorage et cache hors ligne.
5. **Pas de démo sur les boutiques de vrais clients**. Préférer Supabase local/staging avec données entièrement fictives et comptes fictifs. L'instance de production n'a actuellement aucun compte caissier ; ne pas en créer sur les boutiques existantes par automatisme. Supabase Branching peut être payant : ne pas activer sans autorisation.
6. **Contrôler les workflows et signaler les écarts**. Tester mobile/ordinateur sur la preview, notamment affichage des dialogues, retour réseau et transfert sécurisé.
7. **Ne pas fusionner la PR #28 ni déployer en production avant validation explicite**. Ne pas toucher au tarif, au code de PR #22, à la production Supabase ou aux clients, ni exécuter `supabase/rollback/*` sans nouvel accord du propriétaire.
8. Rendre un compte rendu factuel : commits, tests et logs, captures si navigateur, erreurs, risques restants, préparation à la publication.

## Points bloquants pour la mise en service

- Démonstration de vraie séparation entre JWT propriétaire et caissier.
- CI test-web/test-db vert sur dernier commit.
- Essais navigateur avec comptes fictifs Supabase Auth.
- Passage sur iPhone / Android / ordinateur.
- La passerelle QR/social, les images des commandes clients et le panier multi-articles hors-ligne persistent dans d'autres chantiers et ne doivent pas être déclarés terminés.

**En cas de difficulté** : documenter l'erreur exacte, le fichier, le test et la prochaine action utile ; jamais dire « prêt en production » à partir de tests simulés seuls.
