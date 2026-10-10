# COVI

**COVI — Le système d’exploitation de votre commerce.**

COVI est un outil de pilotage simple pour les petits commerces africains. Il relie les arrivages, le stock, les ventes, les charges et la rentabilité sans exposer la complexité d’un ERP traditionnel.

## Parcours métier V1

`ARRIVAGE → COMMANDE FOURNISSEUR / BALLON → PRODUITS → STOCK → VENTE → HISTORIQUE → BÉNÉFICE → STATISTIQUES`

### Fonctionnel aujourd’hui

- Authentification et création du commerce
- Stock réel, quantités et pièces uniques
- Commandes fournisseurs et ballons / lots mixtes
- Pays d’origine recherchable dans la liste des régions reconnues par le navigateur
- Photos produits privées dans Supabase Storage, accessibles uniquement au propriétaire
- Historique détaillé des ventes et vue détaillée de la rentabilité des arrivages
- Charges modifiables et supprimables avec filtre de période
- Cycle brouillon → commandé → en transit → reçu
- Ajout de références fournisseur avec quantité
- Découverte progressive des pièces d’un ballon
- Vente avec prix initial, prix réellement vendu et moyen de paiement
- Décrémentation atomique du stock
- Historique des produits vendus
- Charges de la boutique
- Rentabilité par arrivage et récupération de l’investissement
- Dashboard et statistiques sur données réelles
- Cache local du stock
- File de ventes hors connexion, reprise automatique et anti-doublon
- État de synchronisation visible
- Paramètres du commerce
- Application desktop Tauri
- Build automatisé d’un installateur Windows NSIS

## Stack

React · TypeScript · Vite · Supabase/PostgreSQL · Tauri · GitHub Actions · Vercel

## Développement

Node 22 (≥ 22.13) est requis.

```bash
npm ci                # installe les dépendances (versions exactes du package-lock)
npm run dev           # serveur de développement Vite
npm run build         # vérification des types puis build de production (dist/)
npm run tauri build   # installateur desktop
```

### Qualité

| Script                 | Rôle                                                                                                  |
| ---------------------- | ----------------------------------------------------------------------------------------------------- |
| `npm run format`       | reformate le dépôt avec Prettier (guillemets simples, sans point-virgule, 100 colonnes)               |
| `npm run format:check` | vérifie le formatage sans rien modifier                                                               |
| `npm run lint`         | ESLint (typescript-eslint, règles des hooks React, react-refresh)                                     |
| `npm run typecheck`    | `tsc -b` avec TypeScript 7                                                                            |
| `npm test`             | tests Vitest (`src/**/*.test.ts(x)`, jsdom) puis test de la file hors connexion (`tests/offline.mjs`) |

La CI (`.github/workflows/windows.yml`) exécute ces cinq vérifications et le build sur chaque pull request vers `main`. L’installateur Windows NSIS n’est construit que pour `main` (push ou lancement manuel), après ces vérifications : une modification qui ne compile pas ne produit pas d’installateur.

**TypeScript 7 et ESLint.** TypeScript 7 (compilateur natif) ne fournit pas l’API JavaScript dont typescript-eslint a besoin. Comme le recommande l’annonce de TypeScript 7, le compilateur est installé sous l’alias `@typescript/native` (`npm:typescript@7.0.2`, qui fournit la commande `tsc`) et `typescript` pointe vers `@typescript/typescript6`, utilisé uniquement par le linter. À retirer quand typescript-eslint prendra en charge TypeScript 7.

### Structure

```text
src/
  main.tsx            montage de l’application
  app/                coque : Root (simulation ou application), App (sommaire, barre du bas, menu),
                      routes.ts + useHashRoute (page dans l’URL : #/vendre…), navigation.ts (libellés)
  features/<domaine>/ une page par domaine et ses sous-composants :
                      auth, dashboard, sale, stock, arrivals, expenses, history, statistics, settings, demo, sync
  components/
    icons/            icônes SVG maison (trait 1,75 px)
    ui/               composants du système de design (Button, Field, Amount, Ledger, NumPad…)
                      et anciens petits composants des pages pas encore refaites
  hooks/              hooks partagés (useAsyncData : chargement, erreur, réessai ; useMediaQuery)
  lib/                couche données et utilitaires sans interface :
    supabase.ts         client Supabase typé
    database.types.ts   types générés depuis le schéma Supabase
    types.ts            types métier (Shop, Arrival, Product, Expense, Sale…)
    covi.ts             produits, ventes, photos
    operations.ts       arrivages, charges, tableau de bord, statistiques
    offline.ts          cache du stock et file des ventes hors connexion
    format.ts           montants (fcfa, money : espaces insécables U+00A0), moyens de paiement, accords
    dates.ts            clés de jour et de mois en heure locale, dates dites (« jeudi 8 octobre », « 14 h 32 »)
  styles/             système de design « Le Cahier » (couches CSS) : index.css (point d’entrée,
                      importé par app/Root.tsx), tokens.css, base.css, components.css,
                      app/ (styles propres aux écrans refaits), legacy.css (anciennes classes,
                      limitées à `.legacy`, pour les pages pas encore refaites)
  styles.css          vide, gardé tant que main.tsx l’importe
tests/offline.mjs     test Node de la file hors connexion (charge offline.ts, covi.ts et format.ts depuis les sources)
```

Les montants s’affichent toujours avec `fcfa()` / `money()` (les polices n’ont pas l’espace fine U+202F de `Intl`).

Les tests unitaires sont placés à côté du code (`*.test.ts(x)`). `tests/offline.mjs` réécrit les imports relatifs de `covi.ts` pour le charger hors navigateur : `covi.ts` ne doit importer que `./supabase`, `./offline` et `./format` (plus des `import type`), et `format.ts` doit rester sans import.

Après une migration Supabase, régénérez `src/lib/database.types.ts` (Supabase CLI : `supabase gen types typescript --project-id bmbwmwgfzrijglzcgjut`, ou l’outil MCP Supabase) puis lancez `npm run format`.

La connexion OAuth Tauri utilise le navigateur système et revient à l’application par `covi://auth/callback`; cette URL doit figurer dans Supabase Auth → URL Configuration → Redirect URLs.

## Principes produit

- Puissant derrière. Extrêmement simple devant.
- Vocabulaire métier, pas jargon ERP.
- Les ballons gardent un coût global : COVI n’invente pas un coût d’achat par pièce.
- Les produits vendus restent dans l’historique.
- Les charges de fonctionnement restent séparées du coût des arrivages.
- Le bénéfice affiché est une estimation de pilotage, pas une comptabilité officielle.

## Prochaines couches

Photos produits, synchronisation offline étendue aux écritures autres que les ventes, expérience mobile dédiée, permissions employés, multi-boutiques et distribution Windows signée.
