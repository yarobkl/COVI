# Publier COVI sur l'App Store — liste de contrôle

## Ce qui est déjà dans l'application

| Exigence Apple                                              | Où dans COVI                                                                                                                                         |
| ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Supprimer son compte depuis l'app (5.1.1(v))                | Ma boutique → « Supprimer mon compte » (effacement complet à J+30, annulable)                                                                        |
| Se connecter avec Apple si Google/Facebook (4.8)            | Bouton prêt, à activer : voir `docs/connexion-apple.md`                                                                                              |
| Politique de confidentialité (5.1.1)                        | `#/confidentialite`, liée depuis la connexion, le menu et les pages de commande                                                                      |
| Conditions d'utilisation                                    | `#/conditions`, acceptées à la création du compte                                                                                                    |
| Adresse de support                                          | `#/aide` (contact + questions fréquentes)                                                                                                            |
| Contenus envoyés par des inconnus (1.2) : signaler, bloquer | Chaque commande → « Bloquer ou signaler ce client » ; liste des clients bloqués dans Commandes → QR & liens ; contenus interdits listés dans les CGU |
| Raisons des autorisations (5.1.1)                           | `src-tauri/Info.ios.plist` : appareil photo, photos, position                                                                                        |
| Chiffrement à l'export                                      | `ITSAppUsesNonExemptEncryption = false` (HTTPS seulement)                                                                                            |
| Paiements (3.1)                                             | Aucun achat dans l'app : COVI ne vend pas d'abonnement dans l'app et n'encaisse rien. Ne pas ajouter de bouton « payer COVI » dans l'app iPhone.     |

## Adresses à coller dans App Store Connect

- **Privacy Policy URL** : `https://covi-snowy.vercel.app/#/confidentialite`
- **Terms of Use (EULA)** : `https://covi-snowy.vercel.app/#/conditions` (dans « Licence Agreement », ou garder l'EULA standard d'Apple)
- **Support URL** : `https://covi-snowy.vercel.app/#/aide`

(Avec un nom de domaine à toi, remplacer `covi-snowy.vercel.app`.)

## Confidentialité de l'app (« App Privacy »)

- **Pistage (tracking)** : **Non**. Pas de publicité, pas de SDK d'analyse.
- Données collectées, toutes **liées à l'utilisateur**, utilisées pour **le fonctionnement de l'app** uniquement :
  - Coordonnées : **nom**, **adresse e-mail**, **numéro de téléphone** et **adresse postale** (ceux des clients qui commandent) ;
  - Contenu de l'utilisateur : **photos** (articles, photo de profil, photos jointes aux commandes), **autre contenu** (messages des commandes) ;
  - Localisation : **position précise**, seulement si la boutique enregistre sa position ;
  - Identifiants : **identifiant de l'utilisateur** (compte) ;
  - Autres données : ventes, stock, charges de la boutique.

## Ce que toi seul peux faire

1. Compte **Apple Developer** (99 $/an) et un **Mac avec Xcode**.
2. Activer « Continuer avec Apple » (`docs/connexion-apple.md`).
3. Générer et construire l'app iPhone : `npm run tauri ios init` puis `npm run tauri ios build`.
   Le fichier `src-tauri/Info.ios.plist` est repris automatiquement.
4. Icône 1024 × 1024 et captures d'écran (iPhone 6,7" et 6,5", iPad si l'app est proposée sur iPad).
5. **Compte de démonstration** pour l'équipe d'Apple : créer une boutique de test avec quelques
   articles, un caissier (prénom + code) et le code du responsable, puis les donner dans
   « App Review Information » avec cette note :
   > COVI est un cahier de caisse pour les boutiques. Connectez-vous avec le compte de démonstration.
   > Code du responsable : …… ; caissier « … », code …… . La suppression du compte est dans
   > Ma boutique → Supprimer mon compte.
6. Classification par âge : répondre « Aucun » partout → **4+**.
7. Catégorie : **Business** (secondaire : Productivity).

## Point d'attention : « pas un simple site emballé » (4.2)

Apple refuse une app qui n'est qu'une page web dans une coquille. COVI a des atouts à mettre en
avant dans la note de revue : ventes hors connexion, caisse multi-caissiers avec code PIN, lecture
de QR code de commande, notifications de la boutique. Ajouter les **notifications push** dans l'app
native renforcera le dossier.
