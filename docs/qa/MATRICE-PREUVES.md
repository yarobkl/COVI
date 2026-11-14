# COVI — Matrice de preuves pour décider GO / NO-GO (GPT-06)

**Statut initial : NON VALIDÉ.** Aucun test de préproduction distant n'a été exécuté par ChatGPT. Les vérifications statiques dans GitHub ne suffisent pas à autoriser une mise en production.

## Statuts normalisés
- **PASS** : preuve exécutable ou observation vérifiable, avec version de commit et cible.
- **FAIL** : résultat observé différent de l'attendu.
- **BLOQUÉ** : scénario impossible à lancer, cause documentée.
- **NON EXÉCUTÉ** : aucun essai.

## Grille de validation des livrables
| Porte de qualité | Scénarios / condition | Responsable exécution | Preuve exigée | État |
| --- | --- | --- | --- | --- |
| GATE-01 — Isolation | URL Vercel pointe vers `stcsjwxmmxnjwisqkudz`, aucune valeur de repli production active | CLA-02 + CLA-07 | Trace de configuration **sans secret** + constat à l'exécution | NON EXÉCUTÉ |
| GATE-02 — Migrations | Toutes versions ordonnées, incl. Salon, pas de tâche purge ciblant prod | CLA-02 | Liste Supabase des migrations réellement appliquées, diagnostics | NON EXÉCUTÉ |
| GATE-03 — Données de test | Seeds idempotents ; 3 commerces, utilisateurs fictifs connectables | CLA-02 | Comptes de test A/B, état DB, issue #68 résolue | NON EXÉCUTÉ |
| GATE-04 — Retail | RET-001..010, soldes, stock et idempotence | CLA-03 | Journal détaillé + assertions serveur | NON EXÉCUTÉ |
| GATE-05 — Restaurant | RES-001..012, QR, permissions, caisse | CLA-04 | Tests E2E + états serveur | NON EXÉCUTÉ |
| GATE-06 — Salon | SAL-001..014, agenda, commissions, paiements, remboursements | CLA-05 | Tests E2E + sorties serveur anonymisées | NON EXÉCUTÉ |
| GATE-07 — Finance | FIN-001..006 et oracle seed, FIN-004 arbitré | CLA-03 + CLA-05 | Calculs attendus/observés, validation propriétaire | NON EXÉCUTÉ |
| GATE-08 — Sécurité | Tests authentifiés A/B et RPC SECURITY DEFINER, accès staff | CLA-02 | Résultats de refus, aucune donnée intertenant | NON EXÉCUTÉ |
| GATE-09 — UI Wave | 390/1280 px, 44 px, compatibilité Salon et QR papier | CLA-06 | Captures/constats versionnés et impressions réelles | NON EXÉCUTÉ |
| GATE-10 — Livraison | CI verte, incident Cloudflare classé, rollback et plan pilote | CLA-07 | Exécutions CI et procédure de retour arrière | NON EXÉCUTÉ |

## Rapport de test minimal standard
```text
ID : SAL-009
Commit GitHub :
Reference ID backend (sans secret) :
Compte / établissement de test fictif :
Préconditions :
Actions :
Attendu (XAF, état, permission) :
Observé (XAF, état, permission) :
Preuve : PR, log caviardé ou capture
Verdict : PASS / FAIL / BLOQUÉ / NON EXÉCUTÉ
Anomalie liée :
```

## Critères d'arrêt immédiat
Projet incorrect, fuite de données entre établissements, double débit possible, stock négatif, incohérence de caisse inexpliquée, migration échouée, ou production potentiellement accessible en écriture depuis l'aperçu de test.

## Décision finale
Le propriétaire autorise explicitement la mise en production **après** revue GPT-06 et correction des FAIL P0. Une CI locale ou un screenshot ne constitue pas une recette opérationnelle. Aucun agent ne fusionne ni ne déploie en production par déduction.
