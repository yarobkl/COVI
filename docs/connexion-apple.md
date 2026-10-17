# Activer « Continuer avec Apple »

L'App Store exige « Se connecter avec Apple » dès qu'une app propose Google ou Facebook
(règle 4.8). Le bouton est déjà dans COVI, **caché** tant que les étapes ci-dessous ne sont pas
faites : un bouton qui ne marche pas ferait refuser l'app.

## 1. Chez Apple (compte Apple Developer, 99 $/an)

Sur <https://developer.apple.com/account/resources> :

1. **Identifiers → App IDs** : créer l'identifiant de l'app (ex. `app.covi.boutique`) et cocher
   **Sign in with Apple**.
2. **Identifiers → Services IDs** : créer un Services ID (ex. `app.covi.boutique.web`), cocher
   **Sign in with Apple** → _Configure_ :
   - Primary App ID : celui de l'étape 1 ;
   - Domains : `bmbwmwgfzrijglzcgjut.supabase.co` et `covi-snowy.vercel.app` ;
   - Return URL : `https://bmbwmwgfzrijglzcgjut.supabase.co/auth/v1/callback`.
3. **Keys** : créer une clé avec **Sign in with Apple**, télécharger le fichier `.p8` (une seule
   fois !) et noter le **Key ID** et le **Team ID** (en haut à droite du compte).

## 2. Dans Supabase

Tableau de bord du projet COVI → **Authentication → Sign In / Providers → Apple** :

- activer Apple ;
- **Client IDs** : le Services ID (et l'App ID pour l'app iPhone), séparés par des virgules ;
- **Secret Key** : générée à partir du `.p8`, du Key ID, du Team ID et du Services ID (le tableau de
  bord Supabase explique comment ; elle expire tous les 6 mois : penser à la renouveler).

Ne jamais mettre le fichier `.p8` ni la clé secrète dans le code.

## 3. Afficher le bouton

Dans Vercel (projet `covi`) → **Settings → Environment Variables** : ajouter
`VITE_COVI_APPLE_SIGNIN` = `true` (Production), puis redéployer. Le bouton noir
« Continuer avec Apple » apparaît au-dessus de Google et Facebook.

## 4. Vérifier

Se connecter avec un identifiant Apple de test : un compte COVI est créé, la boutique se crée
comme avec un e-mail. Si l'utilisateur choisit « Masquer mon adresse », l'e-mail reçu est une
adresse relais `@privaterelay.appleid.com` : c'est normal.
