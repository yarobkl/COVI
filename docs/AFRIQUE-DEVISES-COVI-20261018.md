# COVI — Pays africains, monnaie de référence et risque de conversion

## Périmètre de la nouvelle inscription

Le pays de la **nouvelle entreprise** (et non la nationalité du propriétaire) définit
la monnaie comptable du commerce. Catalogue unique `src/lib/africanMarkets.ts` :
26 pays, 5 groupes de présentation.

| Groupe | Pays / devises |
| --- | --- |
| CEMAC (6) | Congo-Brazzaville, Cameroun, Gabon, RCA, Guinée équatoriale, Tchad : **XAF** |
| UEMOA (8) | Côte d’Ivoire, Bénin, Sénégal, Togo, Guinée-Bissau, Burkina Faso, Mali, Niger : **XOF** |
| CEDEAO hors UEMOA (7) | Ghana GHS, Nigeria NGN, Guinée GNF, Gambie GMD, Libéria LRD, Sierra Leone SLE, Cap-Vert CVE |
| Afrique centrale hors CEMAC (3) | RDC CDF (USD secondaire à terme), Angola AOA, São Tomé-et-Príncipe STN |
| Grands Lacs complémentaires (2) | Burundi BIF, Rwanda RWF |

**Attention à l'appartenance institutionnelle :** Burkina Faso, Mali et Niger ont
quitté la CEDEAO le 29 janvier 2025 mais demeurent dans l'UEMOA et continuent
d'utiliser le XOF. La RDC est géographiquement en Afrique centrale (ONU M49)
mais ne fait pas partie de la CEMAC.

**Devises distinctes :** XAF ≠ XOF. Leur arrimage à l'euro ne crée ni un billet
interchangeable ni le droit de comptabiliser un paiement comme une opération
dans la même monnaie. Ne jamais fusionner les montants XAF et XOF dans une
statistique sans conversion sourcée et horodatée.

**RDC :** monnaie légale et référence comptable CDF. Le dollar USD est stocké
comme une *capacité future de règlement* (`secondary_currency = 'USD'`),
**pas** comme des paiements USD déjà acceptés ni comme une deuxième comptabilité.

Sources :
- [BEAC : deux monnaies CFA](https://www.beac.int/billets-pieces/histoire-franc-cfa/)
- [BCEAO : pays UEMOA](https://www.bceao.int/en/content/presentation-wamu)
- [CEDEAO : départ des trois pays du Sahel](https://www.ecowas.int/press-statement-2/)
- [Banque centrale du Congo : rôle du CDF](https://www.bcc.cd/la-banque/billets-et-monnaie/role-et-enjeux-du-franc-congolais)
- [ONU : pays d'Afrique centrale (M49)](https://unstats.un.org/unsd/methodology/m49/)

## Backend de l'inscription

La migration `20261018011500_covi_market_currencies.sql` :

1. Préserve les monnaies XAF des commerces historiques.
2. Remplace une ancienne contrainte autorisant exclusivement XAF par une
   contrainte autorisant uniquement les codes ISO étudiés.
3. Renforce `create_my_business_with_address` : une entreprise en Côte
   d'Ivoire ne peut être créée en XAF, ni une entreprise au Congo-Brazzaville
   en XOF, ni une entreprise de RDC en USD comme monnaie officielle.
4. Stocke `secondary_currency='USD'` uniquement pour les nouvelles
   entreprises de RDC, sans activer un moteur de conversion.
5. Laisse les anciennes RPC de caisse et d'inscription intactes.

Le front utilise la **même liste de pays** et envoie leur code ISO officiel.
Les villes et arrondissements incomplets restent saisis manuellement.

## BLOQUANT — avant une activation hors XAF en production

Ce changement de référentiel n'est **pas** un lancement de la caisse
multidevise. Plusieurs modules COVI existants ont été construits autour
de XAF et les modules Restaurant utilisent aussi des colonnes et libellés
`*_xaf`. Il faut effectuer au minimum :

- Inventaire de **toutes** les constantes XAF, des arrondis, des devises
  affichées et des champs de données de vente, stock, dépenses, bénéfice,
  remboursement, paiement, notifications, exports et statistiques.
- Représentation Money sûre : monnaie ISO 4217 + montant entier dans la plus
  petite unité monétaire appropriée (ou NUMERIC décimal maîtrisé en SQL) ;
  pas de conversion arbitraire et pas de flottants dans les calculs de caisse.
- Une devise **comptable** fixée par établissement (qui ne peut être modifiée
  après les premières transactions sans migration comptable explicite).
- Pour toute devise de règlement différente (USD en RDC) : montant reçu et
  monnaie d'origine, montant converti et monnaie de compte, taux utilisé,
  sens du taux, horodatage, source du taux, méthode d'arrondi, opérateur,
  éventuels frais et audit. Conserver les originaux intacts.
- Sans taux configuré, refuser un encaissement USD dont on ne peut pas
  déterminer la contrevaleur CDF **au moment du règlement**.
- Tests des paiements partiels, rendus de monnaie, remboursements,
  commissions, dépenses et taxes (dans les monnaies pertinentes) ;
  aucun mélange implicite XAF/XOF/CDF/USD dans les totaux.
- Tests SQL des pays/devise sur Postgres jetable et vérification de la
  sécurité multi-établissements. Recette réelle sur les trois secteurs.

**Ne pas publier** ce parcours sur le site principal tant que ces
invariants ne sont pas démontrés, la confirmation e-mail SMTP n'est
pas configurée et l'intégration Restaurant/Salon de la PR #44 n'est pas
validée. La PR #50 reste un brouillon isolé.
