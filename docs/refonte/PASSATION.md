# Refonte « Esprit Wave » — passation

Branche : `feature/covi-refonte-wave` (partie de `main` `3eb0bf7`). PR : brouillon, jamais fusionnée
sans l'accord du propriétaire. Ce document permet à un autre assistant (ChatGPT, Codex…) de
reprendre le travail exactement où il s'est arrêté.

## 1. Le but

Remplacer le style « Le Cahier » (papier quadrillé, marge rouge, écriture manuscrite, police
machine à écrire) par un style **banque mobile** : fond clair et uni, cartes blanches arrondies,
bleu COVI pour l'action, bleu de nuit pour le code caissier, jaune « pièce » pour l'action
principale sur fond bleu. **Rien ne change dans ce que fait l'application.**

Maquette de référence validée par le propriétaire : Accueil sur carte bleue + code caissier bleu
de nuit (artifact « COVI — Comparaison des polices »).

## 2. Règles absolues

1. **On ne modifie que l'apparence.** Fichiers autorisés : `src/styles/**`, `src/components/ui/**`
   (rendu uniquement, jamais les props ni la logique), `index.html` (couleur de thème), `package.json`
   et `package-lock.json` (police uniquement), ce dossier `docs/refonte/`.
2. **Interdit** : toute fonction, appel Supabase, RPC, migration SQL, Edge function, texte métier,
   test existant, nom de classe utilisé par les tests, ordre des éléments qui change un parcours.
   Si un écran ne peut pas être bien restylé sans toucher un `.tsx` de `src/features/`, **s'arrêter et
   demander** au propriétaire, avec le fichier et la raison.
3. Les tests existants restent identiques et doivent tous passer.
4. Ne jamais pousser sur `main`, ne jamais fusionner, ne rien déployer, ne toucher à aucune base.
5. Le module Salon professionnel est dans la PR #64 (non fusionnée). Ne pas le recopier ici ; il
   héritera des variables une fois les deux PR fusionnées. `src/styles/app/salon.css` n'existe pas
   encore sur cette branche : ne pas le créer.

## 3. La charte (source unique : `src/styles/tokens.css`)

| Rôle                  | Valeur                                                | Variable                        |
| --------------------- | ----------------------------------------------------- | ------------------------------- |
| Fond de l'application | `#f4f6fa` (uni, sans quadrillage)                     | `--ground`, `--paper`           |
| Carte / feuille       | `#ffffff`                                             | `--sheet`                       |
| Texte                 | `#0f1b2d`                                             | `--ink`                         |
| Texte secondaire      | `#4a5872` (7,0:1 sur blanc)                           | `--ink-muted`                   |
| Action (bleu COVI)    | `#17408b`, survol `#0f3274`                           | `--action`, `--action-hover`    |
| Bleu de nuit          | `#0b1f45` (code caissier, carte héros)                | `--night`                       |
| Jaune pièce           | `#ffd23f` (action principale sur bleu)                | `--sale-accent`                 |
| Filet                 | `#e3e8f0`                                             | `--line`                        |
| Danger / succès       | `#b3261e` / `#0a6b36` (inchangés)                     | `--danger`, `--success`         |
| Police                | Plus Jakarta Sans 400–800 (`@fontsource`, hors ligne) | `--font-text`, `--font-figures` |
| Chiffres              | même police, `tabular-nums`                           | `--numeric-tabular`             |
| Arrondis              | 10 / 14 / 20 / 28 px                                  | `--radius-1…4`                  |
| Ombre de carte        | douce, jamais de trait décalé noir                    | `--shadow-sheet`                |

Changer de police = modifier les imports de `src/styles/index.css` et `--font-text` /
`--font-figures` (ex. Manrope : `@fontsource/manrope`).

Décors supprimés : quadrillage Seyès (`.seyes`), marge rouge (`.margin-rule`), trait rouge sous les
titres, police manuscrite (`.hand`), ombres « touche » décalées. Les classes restent (les pages
les utilisent) mais n'affichent plus rien de « cahier ».

## 4. Avancement

Légende : ✅ fait · 🔶 en cours · ⬜ à faire

| Étape                                                                      | État |
| -------------------------------------------------------------------------- | ---- |
| Branche, police installée, ce document                                     | ✅   |
| `tokens.css` : palette, police, arrondis, ombres                           | ⬜   |
| `base.css` : fond uni, titres, `.seyes`/`.margin-rule`/`.hand` neutralisés | ⬜   |
| `components.css` : boutons, champs, fiches, listes, dialogues, badges      | ⬜   |
| `app/shell.css` : en-tête, barre du bas, sommaire ordinateur               | ⬜   |
| Accueil (`app/dashboard.css`) : carte bleue des ventes du jour             | ⬜   |
| Vendre et pavé PIN (`app/sale.css`, `app/team.css`) : bleu de nuit         | ⬜   |
| Stock, arrivages, ventes, charges, bilan (`app/pages.css`)                 | ⬜   |
| Commandes en ligne et pages client QR (`app/orders.css`)                   | ⬜   |
| Connexion, création de boutique (`app/auth.css`)                           | ⬜   |
| Notifications (`app/notifications.css`)                                    | ⬜   |
| Restaurant (styles dans `app/pages.css`)                                   | ⬜   |
| Captures avant / après 390 et 1280 px, sans débordement                    | ⬜   |
| Toutes les vérifications vertes, PR brouillon à jour                       | ⬜   |

Mettre à jour ce tableau à chaque commit.

## 5. Vérifications avant chaque commit

```bash
npx prettier --check .
npm run lint
npx tsc -b
npm test          # vitest + offline + kitchen_push + assistant
npm run build
```

Aucun fichier SQL n'est touché : la suite SQL n'a pas besoin d'être relancée.

## 6. Captures

Banc local (hors dépôt) : un faux serveur Supabase renvoie quelques produits et ventes d'exemple,
l'application tourne avec `VITE_SUPABASE_URL=http://localhost:5321 npx vite --port 5320`. Les
captures « avant » ont été prises sur Accueil, Stock, Vendre, Ventes (390 et 1280 px). Pour chaque
écran restylé : capture après, aucun débordement horizontal (`scrollWidth - innerWidth = 0`).
