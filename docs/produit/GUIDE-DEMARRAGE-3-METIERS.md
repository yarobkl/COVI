# COVI — Premier démarrage des trois métiers (GPT-07)
**Version pilote — à vérifier sur la préproduction avant publication.** Ce guide décrit l'usage attendu, sans présenter une fonction non confirmée comme disponible. Devise de l'exemple : FCFA (XAF).

## Promesse affichable dans l'application
**COVI — Outils de gestion opérationnelle, financière et humaine des PME.**

COVI aide un commerçant à enregistrer son activité quotidienne, à retrouver son historique et à distinguer ventes, entrées d'argent, dépenses et résultat de pilotage estimé.

Ne jamais dire « vous gagnez 100 000 » lorsque seul le chiffre d'affaires est connu.

## Avant la première utilisation
- Vérifier la devise et les informations de la structure (activité, localisation, nom, contact).
- Choisir qui est autorisé à enregistrer une opération et qui peut la corriger.
- Protéger le compte propriétaire et les codes de caisse.
- En démonstration, n'utiliser que des produits, montants, rendez-vous et contacts fictifs.
- En production, donner une explication claire des autorisations, de la collecte de données et des modalités de paiement disponibles.

## Boutique — comprendre son stock et ses ventes
**Objectif du premier jour :** enregistrer un article, l'encaisser, le retrouver dans l'historique.

1. Créer un arrivage de démonstration (commande fournisseur ou ballon/lot mixte si utilisé).
2. Enregistrer 3 unités d'un article au prix indicatif de 5 000 FCFA.
3. Ouvrir **Vendre**, sélectionner 2 unités, vérifier le total **10 000 FCFA**.
4. Choisir le moyen de paiement réellement reçu ; ne pas déclarer un virement Mobile Money confirmé si l'opérateur ne l'a pas confirmé.
5. Valider une fois, retrouver le ticket et le stock restant **1 unité**.
6. Ouvrir l'historique et le bilan. Expliquer : **10 000 FCFA vendus n'est pas un bénéfice** ; il reste les coûts d'achat, dépenses et autres charges.

**Cas particulier ballon :** si seul le coût global du lot est connu, suivre le montant encore à récupérer plutôt que d'inventer un coût d'achat pièce par pièce.

## Restaurant — tables, carte et service
**Objectif du premier jour :** préparer une salle, enregistrer une commande et l'encaisser.

1. Paramétrer les tables et zones (salle/terrasse) et une carte avec prix.
2. Ouvrir une table fictive T1 ; ajouter 1 plat à 6 500 FCFA et 1 boisson à 1 500 FCFA, total **8 000 FCFA**.
3. Vérifier l'état de la commande côté service et cuisine lorsqu'ils sont activés.
4. Encaisser selon les moyens pris en charge ; confirmer que la table et le service reflètent l'état réel.
5. Faire scanner le QR imprimé de la table : il doit afficher **le bon établissement** et uniquement les informations publiques autorisées.

**Limite à expliquer :** consulter une carte par QR ne signifie pas automatiquement pouvoir payer en ligne ou commander depuis le téléphone. Ces canaux doivent être explicitement activés et validés.

## Salon — prestations, agenda, équipe et caisse
**Objectif du premier jour :** réserver puis encaisser une prestation, avec un historique compréhensible.

1. Configurer les horaires du salon et créer deux collaborateurs fictifs.
2. Ajouter une prestation « Coupe » à **5 000 FCFA** pour 30 minutes et définir les coiffeurs habilités.
3. Créer un rendez-vous à une heure où le coiffeur est disponible.
4. Essayer le même créneau pour le même coiffeur : le second rendez-vous doit être refusé.
5. Ouvrir une note liée au rendez-vous ou à un passage spontané, encaisser **5 000 FCFA** en mode fictif.
6. Retrouver le ticket et consulter **Rapports**. Expliquer la distinction entre CA, coûts directs, commissions dues et montants effectivement versés.

**Remboursements :** réserver la fonction aux rôles habilités, enregistrer un motif ; les corrections d'un mois déjà clôturé attendent la règle de pilotage validée (FIN-004).

**Limite à expliquer :** tant qu'une intégration de paiement opérateur n'est pas disponible, « Mobile Money confirmé » correspond à une confirmation manuelle par le caissier, pas à une preuve automatisée.

## Messages UX prêts à utiliser
- **Aucun article :** « Votre boutique est prête. Ajoutez votre premier article pour commencer à vendre. »
- **Aucune table :** « Créez votre première table, puis ajoutez votre carte. »
- **Agenda vide :** « Ajoutez vos prestations et votre équipe pour commencer à planifier les rendez-vous. »
- **Aucun résultat financier :** « Les chiffres apparaîtront lorsque vous aurez enregistré des opérations. Les ventes et le bénéfice sont deux choses différentes. »
- **Opération incertaine :** « Nous vérifions si l'opération a été enregistrée. Ne la recommencez pas avant d'avoir contrôlé l'historique. »

## Contrôle de publication
CLA-03/04/05 confirment les intitulés exacts, fonctions réellement actives et chemins d'accès dans l'app intégrée. CLA-06 contrôle l'affichage, GPT-07 valide la compréhension avec des commerçants pilotes. **Ne pas diffuser publiquement avant validation de ces étapes.**
