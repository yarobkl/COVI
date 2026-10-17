# COVI — Audit de fiabilité financière et séparation des établissements

Date : 17 octobre 2026. Audit partiel, lecture seule de la production Supabase, changements de libellés sur branche non déployée.

## Politique non négociable

> COVI — Outils de gestion opérationnelle, financière et humaine de l’entreprise.

La direction artistique « Le Cahier » est conservée. Aucun déploiement, aucune migration SQL, aucune mutation de données réelles pendant cette phase. Un calcul non démontré exact ne doit **jamais** être étiqueté « bénéfice net », « solde en caisse » ou « rémunération payée ».

## Constats vérifiés (production Supabase, SQL de lecture seule)

- RLS activé sur les tables principales `shops`, `sales`, `sale_items`, `products`, `arrivals`, `shop_expenses` et `stock_movements`, avec politiques propriétaires / membres selon le cas.
- **0** lignes `sale_items` rattachées à un produit d'un autre `shop_id` que leur vente, pour les lignes actuellement présentes.
- **0** produits rattachés à un arrivage d'un autre établissement.
- **0** mouvements de stock rattachés à un produit d'un autre établissement.
- **0** ventes dont `total_amount` diffère de `SUM(sale_items.quantity × sold_unit_price)` de plus de 0,005 FCFA pour les ventes avec lignes présentes.
- Ces constats portent sur l'état présent de la base, **pas** une preuve que toutes les futures entrées et API respectent ces invariants.

## Risques identifiés et état

1. **Tableau de bord : « ventes moins charges » ≠ bénéfice ni cash disponible.** Le calcul actuel dans `src/lib/operations.ts` est `SUM(sales.total_amount) - SUM(shop_expenses.amount)`; il omet le coût des marchandises vendues et d'autres éléments. **Mesure déjà prise sur branche** : libellé rendu explicite et note de portée; formule non présentée comme bénéfice net.
2. **Solde d'arrivage : `revenus générés - coût total du lot`** mesure une récupération d'investissement _sur cet arrivage_, mais n'est pas la marge réalisée sur les unités effectivement vendues, ni le résultat net de l'entreprise. **Mesure déjà prise sur branche** : renommage de l'indicateur et note d'interprétation; ne pas changer la comptabilité passée sans décision métier.
3. **Limite API / pagination :** `dashboard`, `liveStatistics`, `arrivalProfitability` utilisent des `.select(...)` sans pagination systématique puis additionnent en JavaScript. En cas de croissance (par ex. au-delà du plafond de lignes PostgREST), les totaux peuvent être **sous-évalués silencieusement**. **À corriger avant rapports financiers certifiés** : sommes / comptes au niveau PostgreSQL avec `numeric`, pagination exhaustive des lignes détaillées, comparaison indépendante, et erreur explicite si le calcul ne peut être complet.
4. **Données de démonstration :** `dashboard` exclut `is_test=true`; `liveStatistics` inclut aujourd'hui les ventes de test et l'indique en sous-titre. **À corriger avant bilan réel exportable** : un paramètre de mode explicite, rapports réels excluant toujours les tests, aperçus de démo séparés et visiblement identifiés.
5. **Périmètres temporels / fuseaux :** `dashboard` calcule les frontières depuis l'heure du terminal local; `expenses` utilise une borne basse et pas systématiquement la borne de fin du mois. **À corriger** : établissement avec fuseau identifié, périodes demi-ouvertes `[début, fin)` côté serveur, conversions UTC explicites et tests changements de mois et d'heure.
6. **Précision des montants :** en JavaScript, `Number` n'est pas une représentation décimale comptable générale; `fcfa` arrondit pour l'affichage. **À faire** : montants en entiers XAF ou `numeric` SQL selon règles métier validées, arrondi fixé, jamais arrondir _avant_ la somme, contrôler les dépassements, décimales et signes.
7. **Isolation SaaS** : le code d'interface utilise `shopId`; ce filtre n'est pas une mesure de sécurité à lui seul. RLS et chacune des fonctions `SECURITY DEFINER` doivent refuser les identifiants d'autres établissements. L'advisor Supabase a signalé de nombreuses fonctions privilégiées exécutables par des comptes connectés : il faut **revoir chacune de leurs autorisations**; cela ne prouve pas une fuite. Certaines tables sensibles RLS sans policy sont volontairement accessibles via fonctions contrôlées; pas d'ouverture arbitraire de policies.
8. **Multi-établissements :** `AuthGate` sélectionne actuellement une boutique propriétaire avec `.limit(1)`. Ce fonctionnement ne doit pas servir de base à des bilans multi-sites avant sélection explicite de la boutique active et tests de périmètre sur toutes les écritures.

## Contrats de calcul à implémenter et tester

- **Vente encaissée** : somme des lignes au prix effectivement facturé / confirmé, remises, remboursements et annulations tracés. Ne pas confondre panier en cours, commande acceptée et paiement confirmé.
- **Chiffre d'affaires encaissé** : transactions encaissées et confirmées sur la période, nettes des remboursements associés selon période et règles explicitement affichées; paiements en attente exclus.
- **Coût des produits réellement vendus (CMV)** : sorties de stock au coût imputable aux articles vendus, avec stratégie de valorisation documentée (par lot, coût moyen pondéré, etc.); un achat de 100 articles dont 10 vendus n'entraîne pas 100 coûts en CMV.
- **Marge brute** = chiffre d'affaires de ventes − coût des marchandises/ingrédients/consommables imputés aux ventes. Si le CMV est inconnu, afficher `non calculable` ou `estimation`.
- **Résultat opérationnel estimé** = marge brute − charges de fonctionnement − rémunérations/charges salariales comptabilisées, sans déduire deux fois une paie déjà comptée comme charge.
- **Trésorerie** = solde initial + encaissements effectifs − décaissements effectifs (incluant achats de stock, paie versée, charges), sans compter les sommes dues non payées et en séparant les moyens de paiement.
- **Paie** : salaire prévu ≠ salaire acquis ≠ salaire versé; avances, commissions, primes, retenues conformes et versements tracés à part; bulletins officiels uniquement après règles locales vérifiées.
- **Vente restaurant** : commandes, additions de table, boissons servies, caisse et paiements résolus sur le même `shop_id` / session; paiement partiel ne libère pas la table; stock jamais déduit deux fois.
- **Exports** : Excel et PDF issus de la même source de chiffres et du même filtrage serveur; `SUM`/comptages réconciliés, pas de limite invisible; libellés précisant `réel`, `test`, `prévu` et `estimé`.

## Suite des vérifications avant GO

- Créer tests multi-comptes avec deux établissements et identifiants de produits / ventes de l'autre; tester directement REST, RPC et fonctions Edge, pas seulement l'UI.
- Tester minimum **0, 1, 1001 et 10 000** ventes par établissement et exports Excel/PDF; comparer SQL `numeric` ↔ tableau de bord ↔ export et détecter toutes les pages manquantes.
- Tester réassorts, rupture, annulation, remboursement, perte, réattribution d'articles, ventes simultanées, arrêt réseau, idempotence des paiements, paie mensuelle et clôture annuelle.
- Tester périodes locales (minuit, changement de mois, nouvelle année), signes négatifs, zéro, coûts incomplets, transferts entre établissements sans double comptage.
- Auditer `SECURITY DEFINER` et exécuter le linter de sécurité avant mise en ligne : https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable
- Conserver un journal de rapprochement automatisé et bloquer les rapports financiers en cas de données incomplètes, plutôt que d'afficher un résultat plausible mais faux.

## Porte de sortie

**Statut : audit initial seulement — fiabilité complète non attestée.** La PR reste en brouillon et aucune promotion en production n'est autorisée tant que les risques de pagination, mode test, arrondis, périodes, RLS/RPC, paie et réconciliation n'ont pas été traités et testés.
