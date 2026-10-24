# Préproduction COVI — procédure d'installation

Projet Supabase de test : **`stcsjwxmmxnjwisqkudz`** (organisation « Testcovi », compte séparé,
eu-west-3). Production : `bmbwmwgfzrijglzcgjut` — **ne jamais y écrire**.

## Règles

1. Avant toute écriture, afficher le Reference ID de la cible. S'il n'est pas exactement
   `stcsjwxmmxnjwisqkudz`, arrêter.
2. Aucune donnée réelle : uniquement les fichiers de ce dossier (données fictives).
3. Aucun secret dans le code, les journaux ou les messages.
4. Si une migration échoue : diagnostiquer avant de continuer, ne pas forcer les suivantes.

## Ordre d'installation

1. Code de référence : branche d'intégration des PR #64 (Salon) et #66 (refonte)
   (`git merge` de `feature/covi-refonte-wave` dans `feature/covi-salon-professional-v1`, sans conflit
   au 24/10 ; 367/367 tests web et toutes les suites SQL vertes).
2. Appliquer les **72 migrations** de `supabase/migrations/` dans l'ordre des noms de fichier, **sauf** :
   - `20261015161000_account_purge_schedule.sql` : en production, elle programme chaque nuit un
     appel HTTP vers l'adresse de la **production**. Sur la préproduction, appliquer à la place
     `preprod_account_purge_schedule.sql` (aucune tâche planifiée), sous le même nom de migration.
3. Charger `seed_retail_restaurant.sql` puis `seed_salon.sql` (rejouables, validés en local le 24/10 :
   3 établissements, 2 ventes = 51 000 FCFA, stock robe 5 → 4, 6 tables, 5 plats, 10 rendez-vous salon).
   Puis exécuter `verify_preprod.sql` (lecture seule) : chiffres attendus, RLS active partout, aucune
   référence à la production, isolement entre établissements.
4. Créer les comptes de connexion de test directement dans la préproduction ; ne jamais écrire leurs
   mots de passe dans le dépôt.
5. Aperçu Vercel de test : définir **`VITE_SUPABASE_URL=https://stcsjwxmmxnjwisqkudz.supabase.co`** et
   `VITE_SUPABASE_PUBLISHABLE_KEY` (clé publique de la préproduction). Sans ces variables,
   `src/lib/supabase.ts` se rabat sur la **production** : vérifier avant tout test.
6. Fonctions Edge (paiement, assistant, notifications cuisine) : non déployées au départ (elles demandent
   leurs propres secrets) ; ces parcours restent indisponibles en préproduction.

## Décision en attente (propriétaire)

Remboursement Salon après clôture du mois (revue GPT sur la PR #64, cas FIN-004) : recommandation de
garder le mois d'origine intact et de compter l'ajustement dans le mois du remboursement.
