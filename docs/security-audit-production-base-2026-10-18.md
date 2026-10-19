# COVI — audit de sécurité basé sur la production (18 octobre 2026)

**Décision : NO-GO pour tout déploiement ou fusion sans revue d'exploitation.**

## Point de départ vérifié

- Déploiement Vercel de production : `covi-snowy.vercel.app`.
- Branche : `claude/caisse-multi-caissiers`.
- Commit de départ : `2e48893ad0d5171c51c6f316814961260a4a218c`.
- Branche de correction séparée : `audit/covi-production-safe-integration-2026-10-18`.
- La PR expérimentale n°22 comporte une autre architecture de caisse : ne pas la fusionner.

## Correctif de passerelle dans la PR n°47

Le code précédemment déployé choisissait implicitement :

- une passerelle publique activée si `COVI_GATEWAY_ENABLED` était absent ;
- l'origine du site officiel si `COVI_PUBLIC_ORIGIN` était absent ;
- une empreinte de quota dérivée de la clé serveur si `COVI_GATEWAY_PEPPER` était absent.

**Nouveau comportement proposé, non déployé :**

- `COVI_GATEWAY_ENABLED=true` est indispensable ;
- `COVI_PUBLIC_ORIGIN` est obligatoire et explicitement renseigné ;
- `COVI_GATEWAY_PEPPER` doit être un secret indépendant de 32 caractères ou plus ;
- tout paramètre manquant laisse la passerelle fermée ;
- les tests vérifient aussi qu'aucun appel privilégié au backend n'est effectué.

**Risque opérationnel :** ne pas déployer ce correctif sans confirmer au préalable
que l'équipe a configuré les variables nécessaires. À défaut, le canal QR/social
sera volontairement indisponible. Cette indisponibilité est le comportement
sécurisé, mais doit être annoncée et testée.

## Vérifications sur Supabase de production, en lecture seule

Les fonctions `submit_public_order`, `get_public_order_catalog`,
`get_public_order_status`, `consume_public_order_quota` et
`attach_public_order_reference` ne sont pas exécutables par le rôle `anon`
dans les permissions PostgreSQL inspectées.

`confirm_public_order_payment` est exécutable par `authenticated`.
Sa définition vérifiée impose `assert_shop_owner`, verrouille la commande,
exige `p_payment_verified=true` et délègue la vente à `record_cart_sale`.
**Ce booléen représente une déclaration humaine, pas une vérification
automatique de l'opérateur Mobile Money.** Aucun client public ne peut
confirmer l'encaissement par ce chemin.

Ces observations portent sur la définition SQL et ses privilèges.
Elles ne remplacent pas une recette fonctionnelle en environnement isolé.

## Risques non résolus — blocants

1. **Mode comptoir et identifiants partagés :** un PIN de caissier sert à
   attribuer les ventes, mais il ne réduit pas les droits d'un utilisateur
   connaissant les identifiants du compte propriétaire. Séparer les
   authentifications et les privilèges avant de présenter le PIN comme une
   isolation de sécurité.
2. **Données personnelles :** fixer et appliquer la conservation des
   téléphones, adresses, notes et captures de référence. Prévoir la purge
   du stockage privé et des copies dans les champs JSON, tout en préservant
   les factures et justificatifs légalement nécessaires.
3. **Abus réseau :** vérifier la provenance des en-têtes IP de proxy,
   le Turnstile réel, les plafonds SQL, la rotation des liens et la
   résistance aux demandes répétées en conditions de production.
4. **Compatibilité métier :** comparer le stock, l'historique, les
   statistiques, les comptes et le parcours de devis avant de reporter
   une amélioration issue de la branche expérimentale.
5. **Mobile :** tester iPhone, Android, reprise après panne réseau et
   conservation du design « Le Cahier » avant toute publication.

## Conditions à remplir avant d'autoriser une intégration

- [ ] Confirmer en lecture seule la présence des paramètres de passerelle,
      sans consulter ni afficher leurs valeurs secrètes.
- [ ] Tester les comportements activé/désactivé sur une instance isolée.
- [ ] Contrôler les refus `anon`, les RLS, les rôles et la limitation d'abus.
- [ ] Vérifier stock, encaissement déclaré reçu, prénom du caissier et facture.
- [ ] Prévoir la sauvegarde et la procédure de retour arrière.
- [ ] Obtenir l'accord explicite avant fusion, migration ou déploiement.

**La présente revue n'a modifié aucune donnée de production.**
Aucune migration SQL, désactivation de Supabase ou dépense n'a été engagée.
