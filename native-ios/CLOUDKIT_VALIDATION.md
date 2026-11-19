# COVI — protocole de validation iCloud et partage

Audit du 19 novembre 2026. Bundle ID `com.covi.app`, conteneur Apple
`iCloud.com.covi.app`, équipe `UK4UQCQ57G`.

## 1. Contrat CloudKit constaté dans la console Apple

La console Apple de **développement** a reçu ces trois types, tous avec le
champ **`payload` de type Bytes** :

| Type de record | Usage COVI | Base de données |
| --- | --- | --- |
| `COVIAccountIndex` | Répertoire de trois établissements maximum | Privée du propriétaire |
| `COVIEvent` | Renommages, remboursements, dépenses, reçus immuables | Zones privées par établissement |
| `COVIOperationalState` | Stock, tables, commandes, salon, catalogue | Zone privée par établissement |

Chaque record contient la version, le propriétaire et l'établissement dans
sa charge utile vérifiée côté application. Les clés sont établies avec des UUID
stables ; la caisse ne se clôture qu'à réception d'un reçu vérifié.

**Production :** aucun type n'était présent au moment de l'audit. Le dialogue
de prévisualisation annonce trois nouveaux types et trois modifications de
rôles système (`_world`, `_icloud`, `_creator`). **Aucun déploiement de schéma
n'a été effectué.** Vérifier les permissions avant un déploiement, puis valider
sur de vrais appareils. La création des types dans le développement ne rend
pas la synchronisation d'une version TestFlight opérationnelle à elle seule.

Les droits `_world` s'appliquent aux enregistrements publics, pas aux zones
privées utilisées ici. Le code COVI ne crée aucun record dans la base publique.

## 2. Deux appareils du propriétaire — scénarios réels restant à exécuter

Prérequis : deux iPhone physiques avec une version native signée de COVI,
le **même utilisateur Sign in with Apple** et le **même compte iCloud** ;
les capacités CloudKit existantes doivent être fonctionnelles. Ne pas
modifier le provisioning ou les certificats dans ce chantier.

| Scénario | Actions | Résultat attendu |
| --- | --- | --- |
| Répertoire | Créer Boutique, Restaurant et Salon sur A ; ouvrir B | Trois espaces et leurs UUID identiques, pas de doublons |
| Catalogue et stocks | Ajouter article + arrivée de 5 unités sur A ; ouvrir B | Article et mouvement présents, quantité exacte 5 |
| Deux ventes hors-ligne possibles | Stock initial 2 ; vendre 1 hors-ligne sur A et 1 sur B | À la reconnexion, deux mouvements, stock final 0 |
| Dernière unité vendue en double | Stock initial 1 ; vendre 1 hors-ligne sur chaque iPhone | Conflit visible, aucun mouvement ou paiement effacé |
| Restaurant | Ouvrir une table et envoyer un plat sur A ; passer le ticket « Prêt » sur B | État cuisine partagé ; table libérée après reçu vérifié |
| Salon | Programmer sur A puis annuler sur B ; reprendre A | Annulation et historique conservés |
| Agenda concurrent | Réserver le même coiffeur sur chaque iPhone hors-ligne | Conflit, sans effacer de rendez-vous |
| Finances | Encaisser en espèces sur A ; ouvrir B ; enregistrer une dépense | Reçu et dépense uniques, ni confirmation ni doublon automatiques |
| Reprise | Fermer l'application, couper puis rétablir le réseau | Reprise via jeton CloudKit, pas de perte de données |
| Comptes | Changer le compte iCloud de B après synchronisation | Synchronisation bloquée, aucun mélange de dossiers |

Les **XCTest** simulent deux bases SwiftData indépendantes et vérifient la
fusion, les conflits, les soldes et la non-duplication. Ils ne remplacent
pas cette validation avec le service CloudKit réel.

## 3. Collaborateurs utilisant un autre compte Apple

Le modèle actuel repose sur `privateCloudDatabase` et est correctement isolé
pour le propriétaire. Il **ne partage pas** les dossiers avec un employé ayant
son propre identifiant Apple.

Apple fournit `CKShare` et une `sharedCloudDatabase`. Cependant, un participant
ayant les droits **readWrite peut modifier ou supprimer n'importe quel record
de la zone partagée**. Partager directement les zones de caisse, reçus et stock
avec ces droits donnerait trop de pouvoir à un simple serveur ou caissier.

Le partage du personnel doit respecter au minimum :

1. Invitation nominative et acceptation iCloud, liée à une identité COVI et
   à un établissement précis ; pas de lien public ni de rôle implicite.
2. Une zone de consultation distincte des dossiers financiers sensibles et
   des données privées clients, filtrée selon le métier et le rôle.
3. Une file de commandes **append-only** par collaborateur, vérifiée par le
   propriétaire avant application, avec rôles, acteurs, versions et idempotence.
   Aucun client ne doit pouvoir falsifier un règlement confirmé ou une annulation.
4. Révocation effective des invitations et refus de rejeu des anciennes actions
   après retrait du rôle ; tests multi-comptes et hors-ligne.

**Ne pas activer un `CKShare` en écriture sur les zones actuelles avant ces
garanties.** Une invitation en lecture seule peut être proposée ultérieurement
après une validation explicite des données visibles par chaque rôle.

## 4. État de livraison

- App native : SwiftUI + SwiftData local, réplication CloudKit explicite.
- Simulateur : tests d'intégrité et d'échanges entre deux bases locales.
- Appareils physiques : **non vérifiés**, aucun iPhone connecté à l'exécuteur.
- Schéma : développement préparé ; **production non déployée**.
- Partage de personnel inter-comptes : **non activé pour raison de permissions**.
- TestFlight : **en pause** ; aucune archive ni action sur la signature.

Sources Apple : [Shared Records](https://developer.apple.com/documentation/CloudKit/shared-records),
[CKShare](https://developer.apple.com/documentation/cloudkit/ckshare),
[Déploiement des schémas](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema).
