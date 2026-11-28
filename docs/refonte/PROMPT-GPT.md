# Prompt de reprise pour ChatGPT / Codex

À copier tel quel si Claude s'est arrêté avant la fin de la refonte.

---

**COVI — REPRISE DE LA REFONTE « ESPRIT WAVE » (APPARENCE UNIQUEMENT)**

Tu reprends une refonte visuelle commencée par Claude Code sur le dépôt `yarobkl/COVI`.

1. Lis d'abord `docs/refonte/PASSATION.md` sur la branche `feature/covi-refonte-wave` : la charte,
   les règles et le tableau d'avancement y sont. Reprends à la première ligne ⬜ ou 🔶.
2. Synchronise la branche avec `origin` avant tout commit. Ne réécris jamais l'historique (pas de
   rebase, pas de `push --force`).
3. **Tu ne changes que l'apparence** : `src/styles/**` et le rendu de `src/components/ui/**`. Aucune
   fonction, aucun appel Supabase, aucune migration, aucun test existant, aucun texte métier. Si un
   écran exige de toucher un `.tsx` de `src/features/`, arrête-toi et demande-moi, avec le fichier et
   la raison.
4. Garde la charte exacte de `src/styles/tokens.css` : n'invente aucune nouvelle couleur, police
   ou ombre. Copie la manière dont les écrans déjà terminés sont faits.
5. Après chaque groupe d'écrans : `npx prettier --check .`, `npm run lint`, `npx tsc -b`, `npm test`,
   `npm run build`. Tout doit être vert avant de pousser. Mets à jour le tableau de
   `PASSATION.md`.
6. Vérifie chaque écran à 390 px et 1280 px : aucun débordement horizontal, texte lisible, boutons
   d'au moins 44 px.
7. Interdits : pousser sur `main`, fusionner une PR, déployer, toucher Supabase ou la production,
   exposer un secret. La PR de la refonte reste en **brouillon**.

À la fin, donne-moi : les écrans terminés, les fichiers modifiés, le résultat exact des
vérifications, ce qui reste à faire, et tout ce qui t'a obligé à t'écarter des règles.

---
