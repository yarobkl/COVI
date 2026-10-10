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
  app/                coque : Root (simulation ou application), App (navigations, en-tête), navigation.ts (liste des pages)
  features/<domaine>/ une page par domaine et ses sous-composants :
                      auth, dashboard, sale, stock, arrivals, expenses, history, statistics, settings, demo, sync
  components/         petits composants partagés (logo, vignette produit, erreur de chargement)
  hooks/              hooks partagés (useAsyncData : chargement, erreur, réessai)
  lib/                couche données et utilitaires sans interface :
    supabase.ts         client Supabase typé
    database.types.ts   types générés depuis le schéma Supabase
    types.ts            types métier (Shop, Arrival, Product, Expense, Sale…)
    covi.ts             produits, ventes, photos
    operations.ts       arrivages, charges, tableau de bord, statistiques
    offline.ts          file des ventes hors connexion, ventes refusées, cache du stock et dernière boutique (IndexedDB)
    idb.ts              petite couche IndexedDB (transactions) utilisée par offline.ts
    pwa.ts              état « nouvelle version disponible » (useAppUpdate) ; pwaRegister.ts enregistre le service worker (web seulement)
    format.ts           montants, moyens de paiement, accords (plural)
    dates.ts            clés de jour et de mois en heure locale
  styles.css          styles globaux (classes CSS utilisées par les composants)
tests/offline.mjs     test Node de la file hors connexion (charge offline.ts, idb.ts, covi.ts et format.ts depuis les sources)
tests/e2e/            test de bout en bout hors connexion (Playwright, hors dépendances du projet)
vite.config.ts        React et PWA (manifest, service worker Workbox)
```

Les tests unitaires sont placés à côté du code (`*.test.ts(x)`). `tests/offline.mjs` réécrit les imports relatifs de `covi.ts` pour le charger hors navigateur : `covi.ts` ne doit importer que `./supabase`, `./offline` et `./format` (plus des `import type`), `offline.ts` que `./idb` (et `await import('./covi')`), et `format.ts` comme `idb.ts` doivent rester sans import.

### Hors connexion et PWA

- Les ventes en attente, les ventes refusées, le cache du stock et la dernière boutique chargée (par compte) sont dans IndexedDB (`covi-offline`), avec un miroir en mémoire chargé par `initOfflineStore()` avant le premier rendu. Les anciennes données localStorage (v1/v2) y sont migrées automatiquement ; si IndexedDB est indisponible, localStorage reste utilisé.
- Sans réseau, une session persistée (même expirée) et la boutique mémorisée suffisent pour ouvrir la caisse ; la session est rafraîchie et la file envoyée au retour du réseau, au retour au premier plan et après `TOKEN_REFRESHED`/`SIGNED_IN`.
- Le service worker (web seulement, jamais dans Tauri ni en développement) précache l’application ; les appels Supabase ne sont jamais mis en cache, seules les photos produits signées le sont (50 photos, 7 jours).
- Test de bout en bout hors connexion (Supabase simulé, aucune requête vers le vrai projet) :

```bash
VITE_SUPABASE_URL=https://covi-e2e.supabase.co npm run build
npm run preview -- --port 4173 --strictPort &
PLAYWRIGHT_DIR=/dossier/avec/playwright node tests/e2e/offline-pwa.mjs
```

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
