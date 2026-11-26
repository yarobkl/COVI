# COVI — progression iOS native

## Boutique COVI 2.0 — Arrivages photo

- Capture en série et import groupé, avec sauvegarde locale à chaque photo et reprise de la file par origine.
- Analyse Studio lors de la vérification de chaque fiche. Confirmation manuelle des prix et quantités, protection contre une double entrée de stock à la reprise.
- Tests ajoutés pour 450 captures, le cloisonnement des files et la confirmation répétée. Validation macOS et essai caméra sur appareil à effectuer.

## Boutique COVI 2.0 — Scan en caisse et Studio

- Le diagnostic macOS du premier lot Scan/Studio a réussi les XCTest, la compilation Release pour simulateur et les captures iPhone/iPad.
- Recherche locale par photo dans Vendre, avec sélection manuelle d’un article disponible et maintien de la recherche textuelle.
- Studio recentre le sujet détouré en conservant ses proportions et l’original. Essais visuels sur des vêtements réels et mesures des temps de recherche sur de gros catalogues restent à réaliser.

## Reprise exécutée — 26 novembre 2026, matin

Base vérifiée `766dc77` sur `feature/covi-2-native`. Les recherches de contexte
confirment la Caisse Salon comme prochain écran, après Clients et Fiche client.
La planche `6155DBBE-144F-4B98-BC2A-001713D39598(1).jpeg` a été récupérée
et inspectée. Le build technique 1.0.13 (10051) reste distinct de COVI 2.0.

### Changements enregistrés

- `6b12ff0`, `e2786d4`, `cb2f057`, `3dd831c` : Caisse Salon regroupée en
  ticket et règlement, import d'un rendez-vous, modification du ticket dans
  une feuille native et confirmation fixe. Montant exact en entier vérifié
  à nouveau à la confirmation ; espèces reçues enregistrées et monnaie
  affichée. Rejet des montants insuffisants ou d'un panier dont le prix a changé.
- `5007612` : Catalogue Salon avec onglets Prestations/Produits, recherche,
  ajout dans une feuille et accès aux fiches existantes. Relecture du rôle
  propriétaire/responsable avant création, modification de prix, inventaire
  ou suspension. Un responsable révoqué ou devenu caissier perd ces droits.
- `656e40b` : export de toutes les pages du reçu vérifié en PNG, partage par
  les outils natifs iOS, PDF conservé. Fichiers image temporaires protégés et
  nettoyés après fermeture du partage. Aucun paiement créé par un partage.
- `924c8ab` : captures des deux écrans Salon ajoutées sur iPhone standard,
  iPhone accessibilité XXXL et iPad simulateur. Ces scénarios utilisent
  exclusivement des données synthétiques en mémoire ; aucun compte réel.
- `e2786d4`, `7229f3c` : autorité backend privée renforcée : contrôle d'une
  session Auth existante, liée au bon compte et non expirée, révocation
  d'adhésion relue, et limite de trois établissements actifs, sérialisée
  entre créations concurrentes. Aucun droit public supplémentaire.

### Preuves backend vérifiées

- [PostgreSQL 17, assertions d'autorité](https://github.com/yarobkl/COVI/actions/runs/45766928675)
  réussi ; journal `139729946649`, message `PASS: team authority assertions`.
- [PostgreSQL 17, limite concurrente](https://github.com/yarobkl/COVI/actions/runs/45767340961)
  réussi ; job `139731307702`. Deux connexions concurrentes : la troisième
  création réussit, la quatrième est refusée, exactement trois espaces actifs.
- Les mêmes assertions SQL ont été exécutées localement sous PostgreSQL
  embarqué PGlite ; cela ne remplace pas l'instance Supabase hébergée.
- Les tests utilisent un schéma Auth minimal synthétique dans une base jetable.
  `backend/tests/bootstrap.sql` ne doit jamais être appliqué à Supabase.
- Le connecteur liste COVI `bmbwmwgfzrijglzcgjut` comme `INACTIVE`.
  La référence historique de préproduction `stcsjwxmmxnjwisqkudz` renvoie
  un refus d'autorisation. Le navigateur cloud affiche la connexion Supabase.
  Aucune migration hébergée, aucune clé et aucune donnée de production modifiée.
  Apple/Google, invitations et synchronisation d'équipe restent à intégrer.

### Preuves visuelles et diagnostics récupérés

- `3dd831c`, [diagnostics complets](https://github.com/yarobkl/COVI/actions/runs/45767753580) :
  Debug, **123 XCTest, zéro échec**, Release et 15 captures iPhone réussis.
  Journaux `139732687256` lus, artefact `15093397829` récupéré.
- `924c8ab`, [diagnostics avec iPad et accessibilité](https://github.com/yarobkl/COVI/actions/runs/45767849103) :
  Debug, **123 XCTest, zéro échec**, Release et 19 captures produits.
  Journaux `139733001937` lus, artefact `15093597494` récupéré et inspecté.
- Comparaison iPhone à `6155DBBE` : ticket de Mireille, total de 30 000 FCFA,
  choix du moyen et bouton fixe visibles. Le montant reçu de 35 000 et la
  monnaie de 5 000 sont présents sur iPad ; sur iPhone standard la monnaie
  est sous la zone visible. Le nom de compte est hors capture.
- Le catalogue montre ses deux types, leurs compteurs réels, la recherche,
  trois prestations et leurs prix. Écarts : photos/durées absentes du modèle,
  style des onglets, densité et navigation complète à vérifier.
- Les premières captures révèlent un titre de catalogue trop large et un
  symbole produit inexistant. Correctif `f64afc2` : titre inline, symbole
  `shippingbox`, prestation avant produit, nom de ligne plus compact.
- Sur iPhone XXXL, la disposition horizontale coupe les mots et montants.
  Correctif `060e8ee` : dispositions verticales aux tailles d'accessibilité,
  icônes décoratives fixes et bouton « Encaisser » plus court ; la confirmation
  conserve le montant exact. Nouveau diagnostic à contrôler avant validation.
- La capture iPad confirme les onglets natifs en haut, les deux cartes et le
  bouton fixe. Elle ne valide pas les interactions tactiles ni une orientation
  différente. Aucune conformité complète des 46 écrans n'est annoncée.
- La collecte des captures prend plusieurs minutes. `fdd1def` borne désormais
  chaque commande longue du simulateur à 120 secondes et conserve les images
  partielles en cas d'échec. Les diagnostics antérieurs ont finalement livré
  leurs artefacts ; aucun blocage du code n'a été déduit de la seule lenteur.

### Rapports du Salon

- La planche `57D4B495` a été inspectée. La période se choisit depuis
  l’en-tête, le bandeau distingue prestations et revente, et l’activité
  de l’équipe affiche les tickets, les rendez-vous et les commissions
  enregistrés. Les sommes du rapport s’agrègent en décimal exact sans
  modifier les données historiques.
- Sur `2873f2c`, Debug, **123 XCTest sans échec**, Release et 20 captures
  ont réussi ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45772162190)).
  Le parcours Plus → Rapports est visible sur [iPhone simulé](https://github.com/yarobkl/COVI/actions/runs/45772162190/artifacts/15094329691).
  La comparaison à `57D4B495` confirme le bandeau, les trois collaborateurs
  et les commissions. Les données synthétiques donnent 268 000 FCFA,
  dont 224 000 de prestations et 44 000 de revente, ainsi que 89 600 FCFA
  de commissions. Le bouton natif ne montrait que le chevron.
- Sur `dc92b81`, Debug, Release, **123 XCTest sans échec** et les 20 captures
  ont réussi ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45774535872)).
  La [nouvelle capture iPhone](https://github.com/yarobkl/COVI/actions/runs/45774535872/artifacts/15096597367)
  a été comparée à `57D4B495`. « nov. 2026 » est visible dans la capsule,
  les libellés distinguent un ticket et deux tickets et les chiffres restent
  exacts. Les cartes sont plus hautes que sur la planche et le récapitulatif
  des commissions occupe une carte supplémentaire. Le changement de période
  et les contrôles d’accès aux rapports restent à vérifier sur appareil.
- Le suivi des absences et les demandes publiques représentées par la
  planche restent à intégrer. Leur statut ne peut pas être déduit
  d’un rendez-vous non encaissé.

- Les planches `D2C012FF` (Plus et Paramètres du Salon) et `A30B3A65`
  (Équipe et Rapports service du Restaurant) ont été retrouvées et vérifiées
  par leur contenu. Après Plus et Paramètres, poursuivre les écrans Restaurant de la planche `A30B3A65`.

### Plus et Paramètres

- La référence `D2C012FF` a été vérifiée. Plus ouvre Paramètres depuis
  la carte du profil ou la section Système et affiche le nombre réel
  d’espaces locaux actifs du propriétaire. Les réglages regroupent
  le délai d’inactivité, les accès PIN, la ville, la devise, les moyens
  reçus en caisse et l’état du compte iCloud. La déconnexion est dans
  Paramètres, avec confirmation et conservation des données locales.
- Les captures de Plus et Paramètres utilisent un profil et deux
  établissements synthétiques. Sur [`f201df9`](https://github.com/yarobkl/COVI/actions/runs/45781831876),
  Debug, Release et **123 XCTest sans échec** ont réussi. La [capture de Plus](https://github.com/yarobkl/COVI/actions/runs/45781831876/artifacts/15098539393)
  confirme la carte du profil, le compteur 2/3 et les sections de gestion
  et de système. Les lignes sont plus hautes que sur la planche. Le scénario
  Paramètres n’a pas atteint sa destination. Le correctif utilise une route
  typée commune pour Paramètres et Rapports et resserre les cartes.
- Sur `457b750`, les journaux confirment Debug, Release et **123 XCTest
  sans échec** ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45783741110)).
  Les [captures iPhone de Plus et Paramètres](https://github.com/yarobkl/COVI/actions/runs/45783741110/artifacts/15100957009)
  ont été comparées à `D2C012FF`. Plus montre le profil, le compteur
  2/3, les accès du salon et les trois premières lignes système.
  Paramètres affiche le délai de 2 min, les accès PIN, la règle de
  remboursement, le commerce et la liste de moyens disponibles dans la
  caisse. Les lignes sont plus hautes, la barre d’onglets reste visible
  dans Paramètres et la déconnexion demande de défiler. L’en-tête de compte
  et les statuts iCloud réels sont hors de la capture.
- Les 20 captures iPhone, dont deux en taille d’accessibilité XXXL,
  ont été conservées. Le scénario complet a dépassé le délai de 18 min
  pendant les étapes iPad. L’artefact n’inclut aucune capture iPad de cette
  révision. Le [diagnostic suivant du même code](https://github.com/yarobkl/COVI/actions/runs/45787970552/artifacts/15102533650) a livré les 22 captures, dont Caisse et Catalogue sur iPad simulé. Les interactions avec les réglages et la déconnexion restent à vérifier sur appareil.
- Les états réels de synchronisation et les paiements activés par espace
  devront être vérifiés avec les fonctions métier correspondantes. La règle
  actuelle des remboursements est affichée sans commande de désactivation.

### Rapports service du Restaurant

- La planche `A30B3A65` a été inspectée. Rapports service place le mois
  dans l’en-tête, le montant net dans le bandeau et les moyens de règlement
  dans la carte d’activité. Le journal CSV conserve les règlements du mois.
- Les montants sont agrégés en décimal exact. Les moyens externes hors
  Mobile Money sont comptés séparément, tout comme les remboursements
  enregistrés. Le ticket moyen utilise les commandes de table clôturées
  avec un règlement dans la période. Les incidents de service restent à
  intégrer au modèle.
- Un test couvre la séparation des moyens, le mois, l’établissement et
  les sommes supérieures à la plage d’un entier 64 bits. Un diagnostic
  ouvre le rapport depuis Plus.
- Sur `9924829`, Debug, Release et **124 XCTest sans échec**, dont le
  cas du rapport Restaurant, ont réussi avec 23 captures
  ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45793932860)).
- La [capture iPhone](https://github.com/yarobkl/COVI/actions/runs/45793932860/artifacts/15105577928)
  a été comparée à `A30B3A65`. Le mois, le bandeau net et brut, les
  pourcentages par moyen, les tickets de table et le bouton d’export sont
  visibles. Les données de test donnent 356 000 FCFA brut, 4 500 FCFA de
  remboursement et 351 500 FCFA net. Les autres moyens représentent
  10 000 FCFA et apparaissent sur leur propre ligne. Les cartes sont plus
  hautes, la barre d’onglets reste visible et les incidents ne sont pas
  représentés. La première capture a révélé une icône d’espèces absente.
  Le correctif emploie le symbole de billet et décline le nombre de tickets.
- Sur `fefe079`, la [nouvelle capture sur simulateur iPhone](https://github.com/yarobkl/COVI/actions/runs/45799016253/artifacts/15108775726)
  confirme les deux icônes de billet et le libellé « 2 tickets de table ».
  Debug, Release et **124 XCTest sans échec** ont réussi sur cette
  révision. Les 21 captures iPhone ont été conservées. Le lancement de
  l’iPad a dépassé 120 secondes, ce qui a fait échouer la phase de captures
  complète. Le changement de mois et l’export restent à essayer sur appareil.

### Équipe et accès du Restaurant

- La planche `A30B3A65` a été inspectée. Depuis Plus, la liste présente
  le propriétaire et les adhésions actives du restaurant. Le détail
  reprend les écrans réellement autorisés et l’état du PIN sur l’iPhone.
  Les réglages du propriétaire restent accessibles via une action dédiée.
- L’écran utilise la politique de navigation existante. Le rôle Caissier
  n’ouvre encore que Plus en Restaurant. L’activation de son flux
  d’encaissement et les invitations par backend restent à intégrer.
- Un test couvre la liste des onglets par rôle. Le scénario iPhone
  comprend quatre membres actifs et une adhésion inactive.
- Sur `3f8b9e9`, Debug et Release compilent, **125 XCTest passent
  sans échec**, dont le test des onglets Restaurant, et 24 captures sont
  disponibles ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45804213643)).
  La [capture iPhone](https://github.com/yarobkl/COVI/actions/runs/45804213643/artifacts/15109313137)
  a été comparée à `A30B3A65`. Les quatre lignes, les badges de rôle
  et les états PIN locaux sont visibles. L’adhésion inactive est absente.
  La carte de réglages et l’ordre alphabétique diffèrent de la planche.
  L’action Inviter dépend encore de l’intégration du backend et les
  interactions administrateur et responsable restent à vérifier sur appareil.
- Les planches `A2188A03` (Cuisine, Encaissement partiel, Incident) et
  `683EE982` (Gestion de la carte, Stock boissons) ont été retrouvées et
  vérifiées par leur contenu. Reprise visuelle sur Cuisine.

### Cuisine du Restaurant

- La planche `A2188A03` a été inspectée. Cuisine affiche le nombre de
  tickets par état, groupe les lignes par table, montre le délai depuis
  l’envoi et ordonne les tickets du plus ancien au plus récent. L’identité
  affichée est celle de l’ouverture de la table lorsqu’elle est connue.
- Les actions par ticket ou par ligne passent par les contrôles existants
  du service. Le traitement groupé valide toutes les lignes avant leur
  changement et écrit une trace par ligne dans la même transaction.
- Le test de régression vérifie le rejet d’un groupe périmé ou dupliqué.
  Le diagnostic iPhone ouvre Cuisine avec trois tables actives.
- Sur `ef01312`, les compilations Debug et Release, **126 XCTest sans
  échec** dont le nouveau test Cuisine et les 25 captures ont réussi
  ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45812714632)).
  La [capture iPhone](https://github.com/yarobkl/COVI/actions/runs/45812714632/artifacts/15114762515)
  a été comparée à `A2188A03`. Elle montre trois tickets à préparer,
  un prêt, un servi, deux lignes regroupées pour la table 01 et les
  délais de 12, 7 et 2 minutes. L’en-tête global est hors capture,
  et les cartes sont plus hautes que dans la planche. Le basculement
  de filtre et les boutons restent à vérifier sur appareil physique.
- La prise en charge distincte, les délais d’urgence, le paiement partiel
  et les incidents présentés sur la planche restent à intégrer.

### Gestion de la carte du Restaurant

- La planche `683EE982` a été inspectée. Plus ouvre un écran dédié
  avec onglets Plats et Boissons, compteurs, recherche, ajout, fiche
  d’édition et interrupteur de disponibilité. La configuration des
  tables conserve sa propre entrée.
- La création et la disponibilité passent par le service, qui relit
  le rôle et contrôle le PIN, les doublons et l’établissement. Une
  demande de disponibilité identique ne crée pas d’événement supplémentaire.
- Un test couvre les doublons, l’isolement et la révocation. Le scénario
  iPhone ouvre l’écran depuis Plus.
- Sur `e36dbde`, les compilations Debug et Release et **127 XCTest
  sans échec** ont réussi, dont le test d’administration de la carte
  ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45821233757)).
  La [capture iPhone](https://github.com/yarobkl/COVI/actions/runs/45821233757/artifacts/15120090159)
  a été comparée à `683EE982`. Elle affiche 4 plats, 1 boisson, la
  recherche, l’ajout, les prix et les interrupteurs. Le Liboké en rupture
  est identifié et désactivé. Les icônes remplacent les photos
  absentes du modèle, et la barre d’onglets est visible. Les interactions
  de recherche, d’ajout et de modification restent à essayer sur appareil.
- Le diagnostic a conservé ses 24 captures iPhone. Le démarrage de l’iPad
  a dépassé 120 secondes. Le workflow isole désormais cette étape,
  arrête le simulateur iPhone avant de démarrer l’iPad et réessaie le
  démarrage une fois. Une vérification du script avec des commandes
  simulées a couvert l’échec initial et la production de deux fichiers.
- Sur `e0f981f`, les compilations Debug et Release, les **127 XCTest**
  et les deux étapes de capture ont réussi
  ([diagnostic macOS](https://github.com/yarobkl/COVI/actions/runs/45824382594)).
  L’[archive](https://github.com/yarobkl/COVI/actions/runs/45824382594/artifacts/15121030170)
  contient 26 captures, dont Caisse et Catalogue Salon sur iPad simulé.
  Le démarrage iPad a réussi au premier essai de cette exécution.
- Les photos, les sous-catégories et le stock boissons avec réservation,
  déduction au service restent à intégrer aux parcours de commande.

### Stock boissons du Restaurant

- La partie droite de la planche `683EE982` présente le stock physique,
  les réservations, le disponible et les actions Réassort et Casse ou perte.
  L’écran SwiftUI est accessible depuis Plus pour le propriétaire et le
  responsable. Le seuil visuel de stock faible est fixé à 10 unités
  disponibles en reprenant les exemples de la planche. Un ancien article
  sans mouvement ni solde affiche « Non suivi ».
- Le service local enregistre les réassorts et les pertes. Chaque ajustement
  crée un mouvement et un événement dans la même sauvegarde, vérifie le
  rôle en vigueur et protège les réservations existantes. Le test ajouté
  couvre la révocation, le cloisonnement, les quantités invalides et les
  pertes supérieures au disponible.
- Sur `02d812b`, les compilations Debug et Release, les **128 XCTest
  sans échec** et les étapes de capture iPhone et iPad ont réussi
  ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45831958162),
  journal `139950743285`). Le nouveau test de stock a réussi. L’archive
  contient 28 captures, dont Stock boissons en taille standard et XXXL.
- La [capture iPhone](https://github.com/yarobkl/COVI/actions/runs/45831958162/artifacts/15124672832)
  a été comparée à `683EE982`. Le retour Plus, Réassort, les quatre
  soldes et les états 32 et 13 en vert, 9 en orange et 0 en rouge
  correspondent aux exemples de la planche. La liste est alphabétique,
  les icônes remplacent les photos, et le bandeau explique les opérations
  locales disponibles. En XXXL, les lignes passent en colonne et le bandeau
  occupe une grande partie du premier écran. Les formulaires et leur
  défilement restent à vérifier en interaction.
- Les réassorts du simulateur sont journalisés et les réservations sont
  injectées dans les données de démonstration. La réservation automatique
  à la commande, la déduction au service et la synchronisation sur deux
  appareils restent à tester ou à intégrer. Le lot 3 se poursuit.

### Encaissement partiel du Restaurant

- La planche `A2188A03` a été vérifiée. Le panneau central présente
  le reste dû, le mode partiel ou complet, les moyens de paiement,
  le montant encaissé et le nouveau reste. La feuille native est
  accessible depuis la table après la demande d’addition.
- Le parcours local enregistre un paiement partiel sur une addition
  figée dont les articles sont servis. Un changement du reste dû
  exige une nouvelle validation. Les espèces sont enregistrées,
  les autres moyens exigent la confirmation de la réception.
  Le reçu complet n’est disponible qu’au règlement du solde.
- Le reste dû est affiché sur la table et le plan. Le rapport inscrit
  chaque encaissement à sa date et compte un ticket à son solde.
  L’écran de remboursement intégral ne propose que les paiements
  Restaurant dont la commande est terminée.
- Une addition partiellement encaissée doit être soldée sur le même
  appareil. Une modification distante incompatible ou un reçu concurrent
  sans les mêmes paiements partiels est refusé et les preuves locales
  sont préservées. La synchronisation des acomptes en cours entre
  appareils et la libération après départ restent à intégrer.
- Sur `a5479af`, Debug, **131 XCTest sans échec**, Release et les
  captures iPhone/iPad ont réussi
  ([diagnostic GitHub](https://github.com/yarobkl/COVI/actions/runs/45837436117),
  journal `139969915465`). Les trois nouveaux tests couvrent le
  règlement en plusieurs fois, le conflit de synchronisation et le
  rattachement du ticket au mois du solde.
- La [capture iPhone](https://github.com/yarobkl/COVI/actions/runs/45837436117/artifacts/15129485288)
  a été comparée à `A2188A03`. Elle confirme Table 01, les deux modes,
  les moyens de paiement et le calcul 28 500 − 15 000 = 13 500 FCFA.
  La feuille s’ouvre depuis la table. Elle présente des pictogrammes SF
  Symbols, les moyens supplémentaires repliés et un bouton Annuler.
  Dans cette première capture, le bouton de confirmation est coupé en
  bas. Le correctif place l’action dans la zone sûre, agrandit la feuille
  et affiche la devise de saisie.
- Sur `e388065`, Debug, **131 XCTest sans échec**, Release et les
  captures iPhone/iPad ont de nouveau réussi
  ([diagnostic GitHub](https://github.com/yarobkl/COVI/actions/runs/45841893290),
  journal `139985439633`, 29 captures). La
  [nouvelle capture iPhone](https://github.com/yarobkl/COVI/actions/runs/45841893290/artifacts/15130376132)
  montre le bouton entier, le montant saisi en FCFA et le solde
  recalculé. Le scénario est réalisé sur simulateur sans confirmation
  de paiement. Les interactions sur appareil physique et la feuille
  à taille de texte d’accessibilité restent à vérifier.

### Aperçu du plan de salle du Restaurant

- Les deux maquettes récentes ont été retrouvées dans le dossier COVI
  et vérifiées par leur contenu. Elles montrent une vue aérienne des
  tables, des statuts et un résumé de la table sélectionnée. La planche
  dédiée distingue le numéro de table, la capacité et les convives.
- L’onglet Tables ouvre une vue Salle alimentée par les tables, commandes
  et paiements enregistrés. Les pastilles mettent en évidence un état
  et conservent la position des autres tables. La liste reste disponible.
  Le résumé ouvre le détail de la session ou la création de session.
- Le dessin dispose les tables dans une grille provisoire et représente
  exactement une chaise par place. Les quatre silhouettes sont attribuées
  selon la capacité en attendant le choix de forme. Les tests ciblent la
  séparation des chaises jusqu’à 100 places et les quatre états affichés.
- Le diagnostic de `36aa342` a réussi à sa seconde tentative après
  l’annulation de la première avant compilation. Debug, Release et
  **138 XCTest sans échec** ont réussi, dont les deux tests de Salle.
  L’archive contient 30 captures, dont Salle sur iPhone. Les captures
  iPad de cette exécution concernent le Salon.
  [GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45858244921/attempts/2)
- La [capture iPhone](https://github.com/yarobkl/COVI/actions/runs/45858244921/artifacts/15139365423)
  a été comparée aux deux maquettes récentes. Elle montre les quatre
  états, huit tables, les dix chaises de Table 10 et le résumé sélectionné
  avec accès au détail. Les pastilles sont sur deux lignes et le plan
  reste une grille. La salle dessinée, l’en-tête, la barre de navigation
  et les actions supplémentaires des concepts ne sont pas reproduits
  dans cette étape.
- Le plan physique éditable, les positions, l’orientation, le zoom,
  les salles et terrasses, la saisie des convives et l’état payé mais
  occupé restent à intégrer. Le parcours tactile, iPad et les tailles
  de texte d’accessibilité de Salle restent à vérifier.
- Les diagnostics du [recentrage Studio](https://github.com/yarobkl/COVI/actions/runs/45856567128)
  ont également été relus sur la base `c44c06a` avec 136 XCTest sans
  échec. L’observation du Studio sur appareil physique reste distincte.

### Configuration du plan de salle

- L’action « Déplacer ou orienter » reprend l’action « Déplacer » de la
  maquette Salle. Le propriétaire ou le responsable peut choisir une
  forme, une orientation par quart de tour et une case sur trois
  colonnes. Deux tables échangent leurs cases si la case cible est
  occupée. L’enregistrement vérifie le rôle courant et le code de caisse.
- La disposition est conservée sur l’appareil par établissement,
  indépendamment des commandes et du schéma SwiftData. Les anciennes
  tables apparaissent dans l’ordre de la liste tant qu’un plan n’est
  pas enregistré. Les nouvelles occupent une case libre. L’ordre des
  tables ou leur occupation commerciale ne change pas leur emplacement.
- Sur `504b176`, les compilations Debug et Release, les **139 XCTest
  sans échec** et les diagnostics iPhone et iPad ont réussi. Les tests
  couvrent les permutations, la réouverture du plan stocké, la géométrie
  des quatre formes pour 1 à 100 places et les états de service. Les
  captures iPad de cette exécution concernent le Salon.
  [GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45863543305)
- Dans les [captures iPhone](https://github.com/yarobkl/COVI/actions/runs/45863543305/artifacts/15140357118)
  comparées à la planche Salle, Table 10 est en troisième colonne sur
  la dernière rangée avec dix chaises. Table 6 est tournée à 90 degrés
  avec six chaises. Le résumé conserve l’accès au détail et ajoute
  l’action de déplacement. La seconde capture montre l’éditeur de
  Table 10 prérempli. Le scénario positionne les tables en mémoire
  avant la capture et ne vérifie pas le geste ni l’appui sur Enregistrer.
- Le placement reste aligné sur trois colonnes. Les salles et terrasses,
  le placement libre et la synchronisation du plan entre appareils
  restent à intégrer. Les interactions sur iPhone et iPad physiques
  restent à vérifier.

### Salles et terrasses du Restaurant

- Le sélecteur de Salle reprend le nom d’espace montré sur la
  planche récente. Le propriétaire ou le responsable peut ajouter
  une salle ou une terrasse, la renommer et y déplacer une table.
  Les compteurs et la sélection suivent l’espace affiché.
- Les positions historiques restent en « Salle principale ». Une
  case est propre à son espace. La permutation reste possible dans
  un même espace. Un déplacement vers un autre espace exige une
  case libre et ne déplace pas ses autres tables. Les changements
  sont enregistrés localement par établissement, avec les contrôles
  de rôle et de PIN.
- Sur `123912e`, les compilations Debug et Release et les **140 XCTest
  sans échec** ont réussi. Le test de reprise reconstruit le format
  historique et vérifie le déplacement, la permutation limitée à
  un même espace, le refus d’une destination occupée et la réouverture
  après renommage. L’exécution a produit 32 captures.
  [GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45871562740)
- Les [captures iPhone](https://github.com/yarobkl/COVI/actions/runs/45871562740/artifacts/15144681293)
  ont été comparées à la planche Salle. Le scénario Terrasse préchargé
  en mémoire montre son nom, ses deux tables et ses propres compteurs.
  En salle principale, le sélecteur peut sortir de l’écran lorsque
  l’ouverture du résumé fait défiler le plan. La création et le
  transfert par interaction, le placement libre et la synchronisation
  entre appareils restent à vérifier ou à intégrer.

### Contrôles iOS et limites

Les premières compilations ont échoué sur une expression SwiftUI ; le découpage
a révélé une chaîne `String` passée au bouton attendant `LocalizedStringKey`.
Le correctif est dans `3dd831c`. Les résultats finaux XCTest, Release et captures
pour `3dd831c` et `924c8ab` figurent ci-dessus après lecture des journaux.
Sur [`060e8ee`](https://github.com/yarobkl/COVI/actions/runs/45770269249),
Debug, 123 XCTest et Release ont réussi. La capture a échoué au lancement
de l’accueil après un délai de 120 secondes. Sur [`2873f2c`](https://github.com/yarobkl/COVI/actions/runs/45772162190),
le lancement direct sous un délai global a livré les 20 captures. Les captures
XXXL de la Caisse et du Catalogue confirment les lignes verticales et le bouton
« Encaisser » lisible. Le détail de caisse demande un défilement à cette taille.

Aucun modèle SwiftData existant n'a été modifié. La conservation d'une ancienne
base installée, les appareils physiques, la synchronisation CloudKit réelle,
les comptes collaborateurs distants et la livraison TestFlight restent non
validés. Les lots Boutique Scan/Studio, QR Restaurant, paiements mixtes/crédit
et les autres écarts du contrat produit ne sont pas déclarés terminés.

Points métier encore observés dans les sources, sans correctif annoncé :
- `RestaurantService.finish` libère actuellement la table au paiement et les
  miroirs CloudKit font de même ; l'état « payé mais encore occupé » et la
  libération physique explicite doivent être traités ensemble, avec leurs tests.
- La caisse Salon exige encore une fiche client ; le parcours universel sans
  identité, hors crédit, reste à harmoniser sans perdre les liens d'historique.
- Le catalogue utilise des symboles natifs : photos, durées structurées et
  ressources proposées par la planche ne sont pas inventées lorsqu'absentes.

## Reprise COVI 2.0 — 25 novembre 2026

Branche active de refonte `feature/covi-2-native`, contrat produit dans
`native-ios/COVI_2_PRODUCT_SPEC.md`. Les chiffres historiques ci-dessous
décrivent la base native du 19 novembre et ne mesurent pas la réalisation de COVI 2.0.

### Validation du dernier lot

- Révision vérifiée `10e3f27`, publiée le 25 novembre 2026 à 19 h 41 (Europe/Paris).
- Correction `36ffdeb` limitant le déverrouillage de caisse au collaborateur et à son établissement.
- Régressions `f2554f1` pour le propriétaire et le caissier entre établissements.
- Action macOS https://github.com/yarobkl/COVI/actions/runs/45677679183, job `139429474448`.
- Compilation de l'application et des tests réussie. Journaux XCTest vérifiés :
  **115 tests exécutés, 0 échec**, dont 13 tests PIN.
- Capture de l'accueil iPhone produite par le workflow. Comparaison aux maquettes encore à effectuer.
- Cette exécution sur simulateur ne valide pas les migrations de données existantes,
  le partage entre comptes Apple ni la synchronisation sur deux appareils physiques.

### Compatibilité SwiftData

- Révision `53ada6e` : compilation et **116 XCTest réussis, 0 échec** sur le simulateur iOS ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45696516004)).
- Le nouveau test vérifie sur disque la conservation de l'établissement, du stock et du mouvement associé après réouverture.
- La comparaison avec la base native `81dc85a` confirme que les modèles, leur liste dans le schéma et la configuration du stockage par défaut sont identiques.
- La validation d'une mise à niveau depuis une ancienne version installée nécessite encore une base de cette version. La recette CloudKit sur deux iPhone signés est décrite dans `native-ios/CLOUDKIT_VALIDATION.md`.

### Lot 2 — Contrôle local des droits

- La sélection des établissements et les opérations métier utilisent la même
  résolution des rôles locaux. Les encaissements boutique et salon exigent une
  adhésion active pour les collaborateurs, en plus du déverrouillage PIN.
- Le service restaurant relit le rôle enregistré à chaque opération. Un écran
  resté ouvert après un changement de rôle perd ses anciens droits à l’écriture.
- Deux tests couvrent la désactivation d’un caissier dont le PIN est déverrouillé
  et le changement de rôle dans le service restaurant. Sur `9933b51`, la
  compilation de l’application et l’étape XCTest sur simulateur iPhone ont
  réussi ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45699387443)).
- Le lot reste en cours. La liaison Apple/Google, les invitations, les sessions
  révocables entre appareils et leurs contrôles serveur nécessitent encore une
  autorité côté serveur. Les règles locales s’appliquent dès réception du
  changement de rôle ou de la désactivation sur l’appareil.

### Backend du lot 2 et TestFlight

- Le propriétaire autorise le choix et la mise en place du backend, ainsi que la livraison TestFlight après validation.
- Supabase Auth et PostgreSQL sont retenus pour la préproduction native. La migration `native-ios/backend/migrations/20261125220000_team_authority.sql` introduit un schéma privé et une résolution serveur des rôles tenant compte des révocations. La migration reste à exécuter et à tester. Le projet historique COVI est inactif.
- Les flux Apple/Google, invitations et sessions restent à implémenter en préservant les établissements existants.
- Le profil de distribution corrigé a permis de signer et livrer la bêta technique 1.0.13 (10051), basée sur `6eb37ed` ([exécution signée](https://github.com/yarobkl/COVI/actions/runs/45706005104)). L’envoi de la refonte COVI 2.0 reste soumis à sa validation visuelle et fonctionnelle.

### Lot 3 — Parcours d’entrée

- L’accueil, la connexion et la création de compte s’adaptent aux grandes tailles de texte. Les formulaires restent centrés sur iPad et les boutons peuvent grandir quand leur libellé revient à la ligne.
- Diagnostics iOS réussis sur [`0b5230d`](https://github.com/yarobkl/COVI/actions/runs/45709003559), [`cd553ef`](https://github.com/yarobkl/COVI/actions/runs/45709647192) et [`aaebcf1`](https://github.com/yarobkl/COVI/actions/runs/45709858546).
- Comparaison de la capture d’accueil d’`aaebcf1` à la planche `5AD6CB67`. Les trois métiers, les titres et les deux actions sont visibles. Les écarts constatés portent sur la flèche placée avant « Commencer », le fond plat et la coupure sous la photo.
- L’accueil réutilise désormais le fond de marque, place la flèche après « Commencer » et fond le bord inférieur de la photo. Les deux actions restent accessibles sous le contenu défilant. Sur [`1c40f85`](https://github.com/yarobkl/COVI/actions/runs/45714877928), 118 XCTest réussis. La capture du simulateur iPhone comparée à la planche confirme la flèche à droite, le fond champagne et le fondu sous la photo. La forme du motif et l’espace entre la photo et les boutons diffèrent encore de la planche. Le rendu aux grandes tailles de texte et sur les appareils physiques reste à contrôler.
- Les planches retrouvées ont été relues et leurs intitulés corrigés dans `native-ios/DESIGN_REFERENCE_MAP.md`. La planche Boutique `9BF220F7` montre Accueil, Vendre et Encaissement. Le parcours Vendre doit garder le panier en haut après la recherche et le total avec son action au bas de l’écran.

### Lot 3 — Boutique

- La planche `9BF220F7` a été inspectée. Sur Vendre, le panier apparaît dans
  une carte juste sous la recherche, au-dessus du catalogue. L’action
  d’encaissement reste au bas de l’écran. Le bandeau qui répétait le titre
  de navigation a été retiré.
- Révision [`4fb3a77`](https://github.com/yarobkl/COVI/commit/4fb3a77589e324c97f2fc37e39cf5c704dbdb66b),
  [compilation et étape XCTest réussies](https://github.com/yarobkl/COVI/actions/runs/45715459342).
  Les photos du catalogue et le raccourci scan suivent leur lot métier.
- Les captures de `87232c4` ont été comparées à la planche `9BF220F7`
  ([images GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45722744021/artifacts/15073282735)).
  Vendre affiche le panier sous la recherche et le total fixe de 35 000 FCFA.
  En espèces, la feuille affiche un montant reçu de 40 000 FCFA et une monnaie de
  5 000 FCFA. La commande de confirmation était sous la zone visible.
- La confirmation reste visible au bas de la feuille pendant le défilement.
  Sur `cf61665`, Debug, 118 XCTest et Release ont réussi ([diagnostics](https://github.com/yarobkl/COVI/actions/runs/45724727588)).
  [Cette première capture du bouton fixe](https://github.com/yarobkl/COVI/actions/runs/45724727588/artifacts/15073324402)
  confirmait sa visibilité dès l’ouverture ; les champs de réception des espèces
  nécessitaient encore un défilement avec les six moyens de paiement.
- Vérification du **26 novembre 2026**, révision `85b2e0` : compilation Debug,
  **118 XCTest réussis, 0 échec**, puis compilation Release sur simulateur,
  sans signature ([diagnostics](https://github.com/yarobkl/COVI/actions/runs/45725061764)).
  Les deux [captures Boutique en français](https://github.com/yarobkl/COVI/actions/runs/45725061764/artifacts/15074478467)
  ont été inspectées : panier regroupé dans une seule carte, total de 35 000 FCFA
  avec action fixe, six moyens de paiement, montant reçu de 40 000 FCFA,
  monnaie de 5 000 FCFA et bouton de confirmation visibles dès l’ouverture
  sur le simulateur utilisé. Les lignes de paiement sont plus compactes et
  l’icône des espèces s’affiche correctement.
- Les captures utilisent exclusivement des données synthétiques en mémoire.
  Elles n’incluent pas l’en-tête de compte ni le statut de synchronisation
  de `RootView`. Elles vérifient le rendu, sans valider les gestes de paiement,
  l’iPad, les grandes tailles de texte, les appareils physiques ni la
  synchronisation multi-comptes. La conformité visuelle complète de COVI 2.0
  et sa livraison TestFlight restent à valider.

- Le commit `87232c4` regroupe les cartes du panier et de l’encaissement
  et ajoute des scénarios de capture avec des données synthétiques en mémoire.
  GitHub Actions a validé Debug, 118 XCTest et Release sur simulateur
  ([diagnostics](https://github.com/yarobkl/COVI/actions/runs/45722744021)).
- Le panier et la caisse partagent désormais le calcul contrôlé du sous-total.
  Un résultat hors limites affiche « Montant invalide » dans le panier et
  bloque l’encaissement. Le test de dépassement couvre aussi ce calcul.
  L’état sélectionné du moyen de paiement est annoncé par VoiceOver.

- L’Accueil Boutique affiche désormais le moyen de paiement enregistré pour
  les dernières ventes. Le résumé du jour distingue les espèces, le Mobile
  Money et les autres moyens. La révision `534449b` ajoute une capture de
  cet écran avec deux ventes créées par le service de caisse dans un stockage
  en mémoire. Debug, 118 XCTest sans échec et Release sur simulateur réussis ([diagnostic](https://github.com/yarobkl/COVI/actions/runs/45731281847)).
- La [capture de l’Accueil Boutique](https://github.com/yarobkl/COVI/actions/runs/45731281847/artifacts/15077287578) a été comparée à `9BF220F7`. Elle confirme la carte de ventes (53 500 FCFA, dont 35 000 en espèces et 18 500 en Mobile Money), l’alerte stock et le moyen de paiement de la première vente visible. Le raccourci Vendre et l’espacement repoussent la seconde vente sous la ligne de flottaison. L’en-tête complet, la densité et la conformité physique iPhone/iPad restent à vérifier.

### Lot 3 — Restaurant

- La première grille suit la planche `2A49F962`. Le nom et la capacité
  tiennent sur la même ligne quand la largeur le permet. Les cartes
  distinguent le total en cours du reste dû après demande d’addition.
  VoiceOver annonce le filtre sélectionné.
- Le scénario simulateur `restaurant-tables` utilise le service natif pour
  ouvrir trois tables et demander une addition dans un magasin en mémoire.
  Il inclut une quatrième table libre. Debug, 118 XCTest sans échec et Release ont réussi sur
  simulateur pour la révision [`74b5386`](https://github.com/yarobkl/COVI/actions/runs/45739778882).
- La [capture de Tables](https://github.com/yarobkl/COVI/actions/runs/45739778882/artifacts/15080604096)
  a été comparée à `2A49F962`. Les filtres et leurs compteurs, les capacités,
  la table libre et les montants de 28 500, 64 000 et 19 000 FCFA sont lisibles.
  Les contours et la hauteur des cartes diffèrent encore de la maquette.
  L’en-tête de compte est hors capture. Les QR et le plan de salle configurable
  relèvent du lot 6. La vue Table 01 et le formulaire de commande restent à capturer.

- Sur `9b685f6`, le détail affiche l’heure d’ouverture de la session,
  la capacité et les états des lignes. Commander propose une recherche native
  et des boutons de quantité de 44 points avec des libellés VoiceOver.
  Le total et l’envoi en cuisine restent au bas de la feuille.
- Les scénarios simulateur `restaurant-table` et `restaurant-order` reprennent
  l’écran de session et le formulaire avec une commande de test enregistrée
  et un panier de brouillon. Debug, 118 XCTest sans échec et Release réussis sur
  simulateur ([diagnostic](https://github.com/yarobkl/COVI/actions/runs/45745812693)).
- Les [captures Table 01 et Commander](https://github.com/yarobkl/COVI/actions/runs/45745812693/artifacts/15084050627)
  ont été comparées à `2A49F962`. La session affiche trois lignes, l’état
  des plats et 28 500 FCFA à encaisser. La commande affiche une recherche
  visible, les onglets Plats et Boissons, les quantités 2 et 1, l’article
  épuisé et l’envoi fixe pour 3 articles à 25 500 FCFA. Les photos, le QR,
  le nom du serveur, les convives réels et le parcours de navigation complet
  restent à vérifier ou à intégrer. Les deux vues en capture sont ouvertes
  directement sur simulateur avec des données synthétiques.

### Lot 3 — Salon

- La planche `058F98E6` a été inspectée. L’onglet Aujourd’hui affiche le
  bandeau du jour, les passages spontanés, les rendez-vous à venir et
  les autres rendez-vous du jour. Le chiffre encaissé est réservé au propriétaire et au
  responsable. Agenda place la création en haut et conserve toute l’équipe
  disponible dans l’éditeur lorsqu’un collaborateur est filtré.
- Sur `29f60be`, Debug et Release compilent et les journaux confirment
  **118 XCTest exécutés, 0 échec** sur simulateur
  ([diagnostics macOS](https://github.com/yarobkl/COVI/actions/runs/45750702103)).
- Les [captures iPhone d’Aujourd’hui et Agenda](https://github.com/yarobkl/COVI/actions/runs/45750702103/artifacts/15086390409)
  ont été comparées à `058F98E6`. Aujourd’hui montre l’action RDV, le bandeau
  avec 4 rendez-vous et 15 000 FCFA, le passage spontané et les deux rendez-vous
  à venir. Agenda montre les filtres, les heures, les colonnes et les deux
  premiers rendez-vous. Sarah est accessible par le filtre ou le défilement.
  L’en-tête de compte est hors capture. Les lignes d’Aujourd’hui sont plus hautes
  que sur la maquette ; sur Agenda, le titre, la date et les couleurs des cartes
  diffèrent. Les deux écrans restent à rapprocher de la maquette et à vérifier
  sur appareil physique.
- La gestion explicite des fauteuils, des arrivées, des absences et des
  demandes en ligne reste à traiter dans les lots métier.
- Nouveau rendez-vous regroupe le client, la prestation avec son tarif,
  le collaborateur et le créneau. La date et la durée se règlent depuis
  la ligne Créneau. La confirmation reste au bas de la feuille et dépend
  du contrôle local de disponibilité. Le service revérifie le créneau à
  l’enregistrement.
- Sur `4cbf619`, Debug et Release compilent et les journaux confirment
  **118 XCTest exécutés, 0 échec** sur simulateur
  ([diagnostics macOS](https://github.com/yarobkl/COVI/actions/runs/45759787263)).
- Les [captures de Nouveau rendez-vous](https://github.com/yarobkl/COVI/actions/runs/45759787263/artifacts/15090135910)
  ont été comparées à `058F98E6`. La feuille affiche les deux modes, les
  quatre lignes, le tarif de 25 000 FCFA et le créneau de 15 h à 17 h. Le
  bouton fixe est actif pour le créneau libre. Lorsque le collaborateur
  a déjà un rendez-vous, l’indicateur passe au rouge et les deux actions
  d’enregistrement sont désactivées. Le rendu diffère par l’espacement,
  l’action Enregistrer dans la barre native et le détail en plusieurs
  lignes. Le dépliage du créneau, le passage spontané et l’enregistrement
  de bout en bout restent à vérifier en interaction sur appareil physique.
- Les planches `C0053217` (Clients, Fiche client) et `6155DBBE`
  (Caisse, Catalogue salon) ont été retrouvées et relues.
- Clients affiche les initiales, les visites associées à des encaissements
  distincts, la prochaine réservation ou la dernière prestation, selon
  les données disponibles. La recherche accepte les numéros avec ou
  sans espaces. La fiche groupe les préférences et notes, montre les
  trois prestations les plus récentes et fixe le bouton de réservation.
  Les statuts de fidélité et d’absence restent à modéliser.
- Sur `86c3123`, Debug et Release compilent. Les journaux confirment
  **118 XCTest exécutés, 0 échec** sur simulateur
  ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45762835810)).
- Les [captures Clients et Fiche client](https://github.com/yarobkl/COVI/actions/runs/45762835810/artifacts/15090249769)
  ont été comparées à `C0053217`. La liste montre la recherche, les
  initiales, une réservation à venir et les trois visites de Mireille.
  La fiche affiche les préférences et notes, trois prestations pour
  70 000 FCFA et le bouton de réservation fixe. La liste présente des
  lignes blanches pleine largeur et des initiales de couleur uniforme.
  L’onglet Clients reste visible sur la fiche. L’en-tête de compte est
  hors capture. Les filtres et états de fidélité ou d’absence dépendent
  de données métier supplémentaires. Recherche, modification et
  réservation restent à vérifier en interaction sur appareil physique.
- Prochain écran à rapprocher de sa référence : Caisse du Salon,
  planche `6155DBBE`.

### Suite du lot 1

Le correctif d’annulation CloudKit `0872560` a également passé la compilation
et l’étape XCTest sur simulateur ([GitHub Actions](https://github.com/yarobkl/COVI/actions/runs/45698668245)).

Auditer la migration SwiftData et les conflits de synchronisation selon le contrat
COVI 2.0, puis ajouter les régressions nécessaires avant les changements d'identité
et d'équipes. Les invitations multi-comptes et le QR restaurant demandent encore
une décision de backend. La conformité visuelle nécessite les références originales.
Le passage TestFlight reste soumis aux validations prévues dans le contrat produit.


Dernier audit : 19 novembre 2026 — dépôt `yarobkl/COVI`, branche source
`feature/covi-native-swiftui-cloud` laissée intacte ; travail isolé sur
`wip/covi-native-20261119-no-testflight` (diagnostic distant).

Le checkout a été reconstruit depuis le dernier commit distant `acd3f383`.
Les changements non publiés du précédent environnement ne figuraient **pas** dans GitHub.
Ce tableau repart donc de l'état **vérifié du code distant**, pas des anciens pourcentages annoncés.

## Critère de notation

- 0 % : absent ; 25 % : squelette ; 50 % : parcours principal partiel ; 70 % : utilisable sur cas normal ;
  90 % : parcours complet, erreurs, états vides et tests compilés ; 100 % : vérifié sur iPhone contre les maquettes.
- **Aucun module ne peut obtenir 90 % sans compilation iOS et tests sur simulateur/iPhone.**
- L'outil Xcode/Swift n'est pas installé dans cet environnement Linux. L'analyse syntaxique locale
  ne remplace pas une compilation ; **les compilations et XCTest réels sont assurés par le workflow
  macOS distinct, sans signature**, détaillé en fin de document.

| Module | Initial distant | Actuel, estimé | Ce qui reste avant 90 % |
| --- | ---: | ---: | --- |
| Coque iOS SwiftUI / navigation | 65 % | 72 % | Validation visuelle iPhone/iPad, tests VoiceOver |
| Accueil et parcours de première ouverture | 55 % | 70 % | Comparaison des 46 écrans approuvés, animations |
| Identité locale sans mot de passe | 0 % | 81 % | Tests XCTest exécutés, récupération/export de compte |
| Connexion native Apple | 0 % | 68 % | Validation réelle Sign in with Apple et profil déjà provisionné |
| Persistance SwiftData locale | 62 % | 70 % | Migration de schéma, tests de corruption/restauration |
| Répertoire d'établissements iCloud privé | 0 % | 65 % | Tests multi-iPhone, collisions et hors-ligne prolongé |
| Journal CloudKit des renommages / remboursements | 40 % | 48 % | Tests de rejeu et résolution des conflits |
| Synchronisation CloudKit **des données métier** | 5 % | 72 % | Schéma préparé en développement dans la console Apple ; pas déployé en production, tests physiques et partage inter-comptes encore nécessaires |
| Multi-appareils propriétaire | 15 % | 74 % | XCTest supplémentaires de convergence et conflits indépendants ; CloudKit réel sur deux iPhone non testé |
| Multi-personnel / rôles | 25 % | 30 % | Invitations, identité stable du personnel, permissions |
| Boutique : catalogue | 65 % | 81 % | Catégories, tests d'usage sur iPhone, synchronisation catalogue |
| Boutique : stock / balles / inventaire | 64 % | 83 % | Historique complet, coût de revient, tests de stock concurrents |
| Boutique : caisse / confirmation manuelle | 75 % | 81 % | Tests physiques, coupure réseau, remboursement partiel |
| Boutique : reçus / historique | 28 % | 84 % | Impression système et tests UI sur iPhone |
| Restaurant : salle et tables | 66 % | 78 % | Réservations, flux multi-serveurs, tests iPhone |
| Restaurant : commandes et cuisine | 64 % | 76 % | Annulation / corrections, calculs avancés, tests |
| Restaurant : règlement en caisse | 66 % | 82 % | Reçu imprimable, tests concurrence et double paiement sur appareil |
| Salon : équipe réelle | 5 % | 79 % | Historique des affectations, rôles, tests UI |
| Salon : agenda / rendez-vous | 61 % | 83 % | Plages horaires avancées, rappels et tests iPhone |
| Salon : catalogue / encaissement | 66 % | 83 % | Corrections et retours avancés, tests multi-iPhone et synchronisation catalogue |
| Salon : clients / fiches | 65 % | 79 % | Consentements, export, suppression, tests iPhone |
| Salon : rapports / commissions | 55 % | 65 % | Périodes, réconciliation financière, tests |
| Dépenses (trois métiers) | 0 % | 82 % | Tests réels multi-iPhone, confidentialité des exports et rapports de marge à ajouter |
| Trésorerie mensuelle multi-métier | 0 % | 79 % | Recoupement sur appareils, tests UI, contrôle des fichiers CSV exportés |
| Paiements externes manuels (sans SDK de paiement) | 65 % | 78 % | Traçabilité du moyen de paiement et reçus réels |
| Sécurité PIN et accès caisse simplifié | 52 % | 76 % | Tests exécutés, parcours d'enrôlement simplifié |
| Aide et accessibilité | 25 % | 30 % | Guide initial, Dynamic Type, VoiceOver, états erreur/vides |
| Conformité aux 46 maquettes | Non vérifiée | Non vérifiée | Maquettes et comparaison sur iPhone indispensables |
| Journal des événements métier local | 30 % | 82 % | Protocole de réplication effectif, purge sécurisée et résolutions de conflits |
| Tests unitaires iOS | 25 % | 90 % | 113/113 XCTest réussis sur `4f037fe` ; parcours physiques et validations CloudKit multi-appareils encore nécessaires |
| Build et tests globaux iOS | 0 % | 86 % | Compilation + 113 XCTest réussis sur macOS sans signature ; tests visuels indisponibles |
| Livraison TestFlight native | En pause | 45 % | Le préflight réel a refusé le profil App Store existant : il ne contient pas les entitlements CloudKit. Archive, schéma Production et traitement Apple restent bloqués ; aucune signature modifiée |

## Changements réellement effectués dans ce lot

1. Restaurer un checkout indépendant du dépôt GitHub d'origine, sans modifier la branche distante.
2. Auditer les instructions de dépôt, schémas, écrans SwiftUI et points d'accès réseau.
3. Remplacer la dépendance Supabase Auth par une session Apple et une identité locale en Keychain.
4. Ajouter le bouton système Sign in with Apple et le contrôle de validité des identifiants restaurés.
5. Fournir un parcours local sans email, mot de passe ni abonnement.
6. Conserver les identifiants locaux entre lancements et éviter l'effacement des données au logout.
7. Supprimer les paramètres Supabase, la vitrine web et les appels REST de la cible iOS.
8. Remplacer la vitrine externe par une fiche native exportable via partage système et QR hors-ligne.
9. Ajouter un répertoire d'établissements privé CloudKit avec fusion prudente et limite 3.
10. Récupérer les établissements après connexion Apple sur un second appareil.
11. Afficher l'état de chargement, l'erreur iCloud et une action de relance.
12. Autoriser la caisse propriétaire sans PIN initial, et imposer le PIN une fois configuré.
13. Fermer la caisse en cas d'erreur Keychain ; valider les quatre chiffres ASCII.
14. Corriger le risque de double décrément de stock par articles dupliqués.
15. Remplacer les collaborateurs fictifs du salon par des fiches SwiftData administrables.
16. Brancher le vrai personnel sur l'agenda, les rendez-vous et les encaissements salon.
17. Préserver l'historique après désactivation d'un collaborateur.
18. Prendre en charge Airtel, MTN, Orange, Moov et espèces avec confirmation en caisse.
19. Construire des reçus natifs vérifiant le total, la remise et les paiements.
20. Brancher le partage des reçus en boutique, restaurant et salon.
21. Ajouter des tests de session, fusion CloudKit, stock, caisse, salon et reçus.
22. Vérifier la syntaxe des fichiers Swift par analyseur syntaxique (aucune erreur détectée).
23. Ajouter une archive iCloud privée immuable des paiements confirmés, indépendante de l'inventaire.
24. Conserver noms, prix unitaires et montants exacts sur les reçus synchronisés.
25. Détecter les doublons, collisions et divergences de montants lors du rejeu de reçus CloudKit.
26. Empêcher qu'une archive distante modifie le stock ou confirme un paiement non enregistré.
27. Ajouter les tests de sérialisation, réimportation idempotente et isolation inter-établissements.
28. Lier définitivement une identité COVI à son compte iCloud privé pour empêcher un changement de compte silencieux.
29. Journaliser la création de produits, les arrivages, les balles et les ajustements de stock boutique.
30. Journaliser la création des tables, les articles de menu et leur disponibilité au restaurant.
31. Journaliser la création, désactivation et réactivation des collaborateurs du salon.
32. Journaliser les créations, modifications et annulations de rendez-vous et de fiches clients salon.
33. Tracer la réception initiale du stock du salon avec un mouvement comptable.
34. Ajouter des tests de cycle restaurant, doubles règlements et événements métier salon.
35. Rendre les journaux Boutique entièrement transactionnels pour création, arrivages et stock.
36. Journaliser les changements de cartes et de tables restaurant, avec retour arrière sur erreur.
37. Associer chaque rendez-vous salon à un acteur et journaliser sa création.
38. Journaliser la modification du profil client salon et les annulations de rendez-vous.
39. Journaliser l'ajout des prestations, produits et quantités initiales du salon.
40. Ajouter un test du parcours complet restaurant : table, commande, cuisine, règlement, idempotence.
41. Empêcher une identité COVI de réutiliser silencieusement le CloudKit privé d'un autre compte iCloud.
42. Persister la fiche de profil locale SwiftData lors de la connexion native.
43. Remplacer les identifiants UUID affichés au personnel par des noms lisibles.
44. Permettre le changement du nom de profil sans connexion réseau et le tester.
45. Déplacer la déconnexion dans les réglages du compte, pour ne pas encombrer l'écran principal.
46. Ajouter une confirmation explicite avant toute déconnexion.
47. Garder l'état de synchronisation discret et compatible avec les petits écrans.
48. Permettre le choix du moyen de paiement réel à la caisse du restaurant.
49. Exiger le montant d'espèces reçu, avec calcul de la monnaie à rendre.
50. Exiger une confirmation humaine explicite pour chaque règlement Mobile Money au restaurant.
51. Refuser le règlement d'une addition vide et toute tentative de deuxième encaissement.
52. Écrire le moyen de règlement effectif et le montant reçu sur le paiement du restaurant.
53. Ajouter des tests pour les espèces insuffisantes, les paiements mobiles non confirmés et les additions vides.
54. Vérifier les détails immuables des reçus iCloud lors de leur réconciliation (libellés, acteurs, périodes, sommes encaissées).
55. Ajouter des tests de divergence entre reçus locaux et reçus déjà archivés.
56. Exécuter pour la première fois l'app et les XCTest en véritable Xcode macOS distant, sans code signing.
57. Isoler la cause des 28 échecs de tests du simulateur : Keychain refuse les opérations sans entitlement (`-34018`).
58. Introduire une abstraction de stockage sécurisé injectable, conservant Keychain dans la production iOS.
59. Remplacer uniquement le stockage des tests par une implémentation mémoire déterministe.
60. Ajouter des scénarios d'échec du stockage sécurisé prouvant que le propriétaire et la session restent bloqués si la clé est inaccessible.
61. Corriger le rafraîchissement de la session PIN pour utiliser la même horloge que les vérifications d'inactivité.
62. Tester précisément la prolongation de session et l'expiration après deux minutes.
63. Permettre au propriétaire de gérer son établissement sans avoir à créer un second code maître.
64. Maintenir la vérification du code maître lorsqu'il a été volontairement configuré.
65. Refuser toute modification sensible lorsque la lecture du stockage sécurisé est indisponible.
66. Distinguer la confirmation d'un remboursement réellement remis de tout paiement automatisé.
67. Ajouter l'édition native des noms et des prix des produits boutique.
68. Refuser les articles dupliqués dans un même établissement (casse et espaces ignorés).
69. Interdire la modification d'un article appartenant à une autre boutique.
70. Conserver les libellés et prix historiques sur les tickets déjà encaissés après modification du catalogue.
71. Journaliser les mises à jour de catalogue de manière transactionnelle.
72. Ajouter des tests pour les changements de prix, les doublons et le cloisonnement des établissements.
73. Afficher les remboursements manuellement confirmés sur les reçus natifs.
74. Conserver l'encaissement d'origine visible même si un remboursement intégral est enregistré.
75. Ajouter la mention de remboursement aux reçus partagés par le système iOS.
76. Vérifier le rattachement du remboursement au bon paiement, propriétaire et établissement.
77. Ajouter des tests de reçu remboursé et de remboursement provenant d'un autre propriétaire.
78. Exiger la confirmation humaine au niveau du service métier salon avant tout encaissement.
79. Tester qu'un paiement salon non confirmé ne touche ni le stock ni les enregistrements de caisse.
80. Ajouter la recherche native de clients salon par nom et téléphone.
81. Afficher des états vides explicites lorsque le salon n'a aucun client ou aucune correspondance.
82. Demander confirmation avant d'annuler un rendez-vous, en conservant son historique.
83. Tester la libération du créneau après annulation et interdire l'annulation d'un rendez-vous encaissé.
84. Ajouter l'édition native des plats, boissons, catégories et prix du restaurant.
85. Protéger les tickets déjà envoyés en cuisine lorsque les prix de la carte changent.
86. Ajouter un test restaurant de mise à jour de menu et de conservation du ticket historique.
87. Ajouter l'édition du nom et de la capacité des tables de restaurant lorsqu'elles sont libres.
88. Bloquer la modification des tables occupées et empêcher les noms de table dupliqués.
89. Vérifier par XCTest que le restaurant interdit le règlement tant que les plats ne sont pas servis.
90. Vérifier par XCTest qu'un plat en rupture ne peut pas être envoyé et qu'aucun ajout n'est possible après l'addition.
91. Obtenir une compilation iOS native sans signature réussie sur un hôte macOS Xcode.
92. Obtenir une exécution complète de 53 XCTest sur simulateur avec zéro échec, zéro code de distribution.
93. Recenser les 23 catégories réelles de dépenses existantes dans la version web COVI.
94. Créer un modèle SwiftData natif pour les dépenses avec montant entier, acteur, catégorie, date et note.
95. Mettre à disposition la saisie des dépenses pour propriétaires et responsables des trois métiers.
96. Construire un journal des dépenses par mois avec total et états vides.
97. Permettre l'annulation non destructive d'une dépense par le propriétaire, en conservant une trace d'audit.
98. Journaliser la saisie et l'annulation de dépense dans l'outbox transactionnelle.
99. Ajouter des tests pour les montants invalides, le cloisonnement, le refus d'annulation non autorisée et l'idempotence.
100. Ajouter un tableau de trésorerie natif utilisable par les trois métiers.
101. Basculer le calcul du chiffre d'affaires sur les paiements réellement confirmés plutôt que les commandes seulement ouvertes.
102. Déduire les remboursements réels et les dépenses actives du mois sélectionné.
103. Regrouper les entrées par moyen de paiement et les sorties par catégorie.
104. Éviter de présenter ce solde net comme un bénéfice comptable ou un solde bancaire.
105. Vérifier la séparation stricte entre établissements et périodes dans les statistiques.
106. Ajouter des tests de calcul et d'exclusion des dépenses annulées.
107. Analyser le diagnostic Xcode de la carte restaurant et corriger la collision entre erreur attrapée et état d'interface.
108. Corriger le même risque d'ombre portée sur les écrans de dépenses ajoutés dans ce lot.
109. Mettre à jour la documentation Xcode pour ouvrir le vrai projet plutôt que recréer un template.
110. Expliquer clairement le mode de diagnostic sans signature ni distribution TestFlight.
111. Ajouter une aide intégrée pour la saisie des dépenses et la lecture du bilan financier.
112. Renforcer les droits d'enregistrement des dépenses : propriétaire ou responsable actif seulement.
113. Ajouter des tests de refus pour les caissiers et les responsables désactivés.
114. Permettre la correction native du nom du client salon sans perdre son historique.
115. Contrôler la longueur des noms, téléphones, notes et préférences avant enregistrement.
116. Tester la modification de fiche client et son journal d'audit.
117. Ajouter les messages d'état vide au catalogue boutique et aux recherches sans résultat.
118. Expliquer clairement l'absence de plats disponibles dans l'éditeur de commande du restaurant.
119. Afficher l'état « aucune commande » dans la cuisine sans laisser un écran vide.
120. Guider le salon lorsque l'équipe, les clients ou le catalogue n'ont pas encore été configurés.
121. Générer un PDF de reçu directement sur l'iPhone avec le moteur PDF natif Apple.
122. Paginer les lignes longues du reçu sans WebView ni bibliothèque externe.
123. Rendre le PDF disponible dans la feuille de partage iOS.
124. Conserver la mention des remboursements dans le PDF partagé.
125. Ajouter un XCTest ouvrant le document PDF avec PDFKit et vérifiant son contenu.
126. Retirer le faux QR de table qui n'effectuait aucune vraie commande native et pouvait troubler le personnel.
127. Remplacer le sélecteur de boutique inutile par un titre simple lorsque le propriétaire n'a qu'un établissement.
128. Réaffirmer la règle produit validée : trois établissements actifs maximum par propriétaire.
129. Unifier cette limite entre l'accueil local, la création SwiftData et le répertoire privé iCloud.
130. Autoriser à nouveau la création après archivage d'un établissement, sans supprimer l'historique.
131. Ajouter un test de la limite multi-établissements et de l'isolation entre propriétaires.
132. Introduire la synchronisation des dépenses entre appareils via CloudKit privé Apple.
133. Répliquer la création d'une dépense comme un fait immuable, sans service web externe.
134. Répliquer séparément son annulation, en conservant la preuve de l'opération initiale.
135. Définir des identifiants déterministes pour rendre le rejeu des annulations idempotent.
136. Gérer les événements CloudKit reçus dans le désordre, grâce à une file locale d'annulations en attente.
137. Refuser les montants, propriétaires, établissements ou contenus contradictoires entre appareils.
138. Lier les marqueurs de dépenses au même compte iCloud privé et conserver un jeton de reprise par établissement.
139. Ajouter des tests de réimportation, désordre des événements, isolation et déterminisme des identifiants.
140. Documenter honnêtement la portée du CloudKit actuel : dépenses et reçus oui, stock et rendez-vous pas encore.
141. Canoniser l'encodage JSON des faits de dépenses pour limiter les divergences de rejeu multi-appareils.
142. Refuser la propagation d'une annulation de dépense émise par une identité autre que le propriétaire.
143. Ajouter un test de rejet des annulations iCloud sans auteur légitime.
144. Signaler à l'utilisateur les annulations de dépenses encore en attente de leur événement d'origine.
145. Ajouter un écran natif d'état des stocks à la boutique.
146. Distinguer quantitativement stock physique, quantités réservées et unités disponibles.
147. Calculer la valeur disponible au prix de vente sans la présenter comme un bénéfice.
148. Signaler les articles faibles et les inventaires incohérents sans fausser les totaux.
149. Ajouter des tests de valorisation, stocks réservés, anomalies et isolation des autres boutiques.
150. Ajouter le changement de créneau d'un rendez-vous salon sans effacer l'historique de réservation.
151. Vérifier les conflits à la fois du client et du collaborateur lors du changement de rendez-vous.
152. Bloquer la modification des rendez-vous annulés ou déjà encaissés.
153. Ajouter un formulaire SwiftUI natif pour déplacer les rendez-vous depuis l'agenda.
154. Préserver le journal métier de modification et l'identifiant stable du rendez-vous.
155. Tester le déplacement, la libération de l'ancien créneau, les collisions et l'accès inter-établissements.
156. Permettre la suspension temporaire des ventes d'un article boutique sans suppression.
157. Préserver les ventes et les mouvements de stock historiques lors de sa désactivation.
158. Interdire toute nouvelle vente d'un article suspendu, même si le panier existait déjà.
159. Permettre la réactivation du catalogue sans recréation ni doublon d'article.
160. Rendre visibles les références suspendues à l'inventaire mais les masquer de la caisse.
161. Journaliser et tester la suspension, la réactivation et l'idempotence des changements d'état.
162. Vérifier que les alertes de stock faible ignorent les références volontairement suspendues.
163. Concevoir un export CSV local iOS ouvrable dans Fichiers, sans service distant.
164. Sérialiser de façon déterministe les colonnes et les lignes de CSV en UTF-8.
165. Échapper correctement les virgules, guillemets et retours à la ligne du contenu.
166. Réduire les risques d'injection de formules dans les tableurs lors d'un export des libellés saisis.
167. Exporter le stock de la seule boutique active, avec ses identifiants et libellés.
168. Inclure le stock physique, les réservations, les disponibilités et les articles suspendus.
169. Exporter le journal mensuel des dépenses avec notes et événements annulés conservés.
170. Ajouter une mise en garde explicite avant la sauvegarde d'un journal pouvant contenir des notes privées.
171. Exporter le bilan financier mensuel dans un tableau CSV cohérent et lisible.
172. Séparer les encaissements, les remboursements, les dépenses et le solde net des flux.
173. Inclure les ventilations par moyen de paiement et catégorie de dépense.
174. Ajouter des tests CSV pour les citations, injections de formules et montants négatifs.
175. Tester l'isolation inter-boutiques lors de l'export des stocks.
176. Tester les exports des dépenses annulées et les agrégats de trésorerie.
177. Centraliser la création de prestations et produits du salon dans un service métier transactionnel.
178. Valider noms, prix, nature de service et niveaux de commission avant création.
179. Interdire les références dupliquées sans distinction de casse ou d'accents.
180. Refuser la modification du catalogue provenant d'un salon différent.
181. Vérifier la commission entre 0 et 100 % pour chaque référence.
182. Distinguer le stock initial des produits physiques et les prestations sans inventaire.
183. Conserver le premier mouvement de stock et sa piste d'audit à la création du produit.
184. Permettre la modification des noms et des prix du catalogue depuis une fiche native.
185. Garder le nom et le prix d'origine sur les tickets déjà encaissés après modification du catalogue.
186. Permettre la correction du taux de commission pour les futures ventes sans réécrire les commissions passées.
187. Conserver l'identifiant du service sur les rendez-vous antérieurs lors d'une édition.
188. Permettre la suspension temporaire d'une prestation ou d'un produit salon sans suppression.
189. Réactiver une référence avec le même identifiant et le même historique.
190. Interdire les nouvelles réservations de prestations suspendues.
191. Interdire l'encaissement direct des références suspendues au niveau du service métier.
192. Préserver la possibilité d'encaisser une prestation déjà réservée avant sa suspension.
193. Afficher la disponibilité dans le catalogue et retirer les références suspendues des sélecteurs de réservation.
194. Ajouter une fiche SwiftUI pour les modifications et la disponibilité des prestations et produits.
195. Permettre le recomptage manuel du stock de soin dans le salon.
196. Interdire un recomptage qui ferait passer le stock physique sous les unités réservées.
197. Consigner les ajustements de stock salon comme mouvements non destructifs avec motif et acteur.
198. Ajouter des tests d'invalidité de catalogue, doublons, limites de taux et isolation inter-salons.
199. Ajouter des tests de prix et commissions historiques ainsi que d'inventaire du salon.
200. Tester le cycle suspension → refus de réservation / vente directe → encaissement d'ancien RDV → réactivation.
201. Éviter le calcul d'un stock négatif ou incohérent lors de l'ajout boutique au panier.
202. Détecter les débordements d'entiers dans l'export CSV d'un inventaire corrompu.
203. Tester l'export d'un inventaire contenant des quantités impossibles sans plantage.
204. Ajouter le franc congolais CDF, le franc rwandais RWF et le franc burundais BIF aux devises initiales.
205. Expliciter la devise de chaque commerce plutôt que de supposer que toute l'Afrique utilise le FCFA.
206. Permettre le choix de la devise dès la création de l'établissement.
207. Empêcher la création dans une devise non prise en charge par les montants entiers.
208. Afficher les devises disponibles dans les réglages propriétaires iOS.
209. Exiger le contrôle du code maître avant une modification de devise existante.
210. Interdire une modification de devise après l'enregistrement de produits, ventes, dépenses ou arrivages.
211. Remplacer les libellés FCFA fixes des prix, remises et reçus boutique par la devise du commerce.
212. Calculer et afficher la monnaie à rendre dans la même devise que l'encaissement boutique.
213. Corriger la devise des coûts de balles, des valorisations et de la saisie de prix.
214. Utiliser la devise de l'établissement pour les prix, additions et montants reçus du restaurant.
215. Utiliser la même devise pour les tickets envoyés en cuisine et les modifications de la carte.
216. Corriger la devise des rendez-vous, encaissements et articles du salon.
217. Corriger la devise du rapport de commissions et des fiches clients salon.
218. Afficher la devise exacte lors de la saisie des dépenses communes aux trois métiers.
219. Ajouter un XCTest de reçu CDF pour vérifier l'absence de conversion ou d'étiquette FCFA erronée.
220. Tester le verrouillage du changement de devise après création d'une dépense ou d'un article, avec isolation inter-commerces.
221. Inclure les arrivages de balles dans le schéma isolé des tests de protection des devises.
222. Vérifier qu'un premier arrivage bloque les changements de devise comme toute autre opération financière.
223. Limiter les collaborateurs affichés dans le rapport salon à la période effectivement sélectionnée.
224. Afficher un état vide explicite lorsqu'un salon n'a ni rendez-vous ni vente dans la période.
225. Préciser que le chiffre après commissions ne déduit pas encore les charges de l'établissement.
226. Définir un format privé CloudKit versionné pour chaque donnée opérationnelle, sans dépendance web.
227. Modéliser les états synchronisables du catalogue, des arrivages et des mouvements de stock immuables.
228. Modéliser les fiches clients, collaborateurs, disponibilités et réservations salon.
229. Modéliser les tables, commandes ouvertes et lignes de préparation du restaurant.
230. Modéliser les historiques de commissions salon et les droits d'accès des responsables.
231. Maintenir les paiements et remboursements dans leurs journaux vérifiés existants plutôt que les déduire d'un état distant.
232. Ajouter un contrôle compare-and-swap CloudKit refusant d'écraser une mise à jour concurrente.
233. Enregistrer localement la dernière version iCloud connue de chaque entité.
234. Refuser une mise à jour distante qui écraserait un changement hors ligne non envoyé.
235. Appliquer les articles et dépendances avant les mouvements, ventes et réservations.
236. Appliquer les entrées de stock une seule fois, sans recopier le compteur physique comme une vérité distante.
237. Vérifier que chaque compteur de stock correspond à la somme de son historique d'entrées et de sorties.
238. Empêcher qu'une quantité incohérente ou concurrente devienne négative après synchronisation.
239. Détecter les rendez-vous en concurrence sur le même créneau, client ou collaborateur.
240. Permettre à un reçu confirmé de terminer une commande restaurant ouverte reçue d'un autre appareil.
241. Refuser le passage de payé à non payé lorsqu'une ancienne commande ouverte arrive en différé.
242. Séparer les synchronisations propres à chaque établissement et à chaque identité iCloud.
243. Intégrer les nouveaux états opérationnels dans la persistance locale SwiftData.
244. Lancer les cycles métiers dans le statut de synchronisation propriétaire sans polling serré.
245. Ajouter des tests de réimportation, inventaires, conflits concurrents et cycle restaurant multi-appareils.
246. Empêcher toute modification rétroactive des mouvements de stock, des balles et des commissions importés.
247. Tester la réplication des annulations de rendez-vous en conservant l'identifiant et l'historique.
248. Tester le refus de deux rendez-vous concurrents pour un même collaborateur.
249. Tester le refus d'une sortie de stock qui ferait passer l'inventaire total sous zéro.
250. Réduire les lectures SwiftData de lignes de cuisine aux seules commandes ouvertes de l'établissement.
251. Conserver exactement les UUID des articles importés afin que stocks, rendez-vous et lignes restent liés.
252. Empêcher qu'un ancien état de table rouvre une addition déjà réglée par un reçu vérifié.
253. Tester l'arrivée du reçu avant un ancien état de salle dans le simulateur.
254. Documenter la réplication CloudKit explicite, les comptes Apple et l'absence de partage du personnel entre identifiants.
255. Auditer les types CloudKit réellement présents dans le conteneur Apple `iCloud.com.covi.app`.
256. Créer les trois types `COVIAccountIndex`, `COVIEvent` et `COVIOperationalState` dans le schéma de développement Apple.
257. Ajouter à chacun un champ `payload` de type `Bytes`, sans toucher aux données métier ni aux profils Apple.
258. Vérifier que le schéma de production est vide et inspecter la prévisualisation de déploiement, sans déployer.
259. Centraliser les noms des record types et du champ `payload` pour éviter des divergences entre le code et CloudKit.
260. Tester deux stocks locaux indépendants avec ventes concurrentes valides et refus de survente du dernier article.
261. Tester les rendez-vous salon concurrents sur deux copies distinctes d'un établissement.
262. Documenter les tests physiques restants et la limite d'ACL de `CKShare` avant toute invitation d'employés.
263. Remplacer la cible hybride de l'ancien workflow TestFlight manuel par le projet SwiftUI/XcodeGen natif, avec préflight XCTest, contrôle du profil CloudKit Production et de Sign in with Apple, version supérieure à 1.0.7 et envoi soumis au drapeau explicite `uploadToTestFlight`. Aucun certificat ni profil Apple n'est créé ou modifié.
264. Exécuter un véritable préflight manuel macOS sans envoi (`uploadToTestFlight=false`, action `44516821945`, commit `8182716`) ; valider l'équipe, le Bundle ID et Sign in with Apple, puis constater le blocage de sécurité : le profil App Store existant ne contient ni conteneur ni service CloudKit ni environnement Production. Arrêt avant compilation/signature/envoi, comme prévu.

## Vérification macOS sans signature (branche de diagnostic uniquement)

Le workflow GitHub Actions `COVI Native iOS Diagnostics` s'exécute sur la branche
`wip/covi-native-20261119-no-testflight`, distincte de la branche Xcode Cloud.
Le second lancement a **compilé l'app et ses tests avec succès** (`build-for-testing`, étape 6).
Il a ensuite exécuté 46 XCTest : 18 réussis, 28 en échec, **dont les erreurs sont toutes liées à
l'accès Keychain non signé** (`OSStatus -34018`, ou refus de caisse qui en découle).
La signature étant volontairement interdite, le stockage sécurisé a été rendu injectable,
avec Keychain inchangé en production et un stockage isolé en mémoire dans les XCTest.
Le troisième lancement de référence (`765f157`, action `44473901012`) a ensuite
**réussi la compilation et les 53 XCTest** sans aucune erreur.
Un quatrième lancement (`b0944ac`) a permis de trouver, au compilateur, deux
affectations ambiguës dans le nouvel éditeur restaurant ; elles ont été corrigées
avant le lancement du lot incluant également dépenses et trésorerie.
Le cinquième lancement (`eebf54c`, action `44475555009`) a **compilé et exécuté
68 XCTest sans aucun échec**. Le lancement ultérieur (`32a49d`, action `44489621987`,
job `135441631979`) a **compilé et exécuté 78 XCTest sans aucun échec**, y compris
le journal CloudKit des dépenses. Les changements de rendez-vous, la suspension boutique
et leurs tests, ainsi que les exports CSV, ont ensuite fait l'objet de
lancements supplémentaires du même workflow de diagnostic.
Depuis, les deux lancements suivants ont également réussi : `3ffe8d4` avec **84/84**
XCTest et `1a6c74e` avec **88/88** XCTest. Le lancement `2b02e7d` a réussi
**92/92 XCTest**, validant le catalogue salon, ses commissions et les blocages
de vente. Le lot de devises d'Afrique centrale et les corrections ajoutées
ensuite ont également été validés : le lancement `68c7de5`, action `44492890062`,
a **compilé l'intégralité du projet et exécuté 97/97 XCTest sans échec** sur
simulateur iPhone macOS, sans signature, sans archive et sans TestFlight.
Ce contrôle ne crée **ni archive de distribution ni provisioning**, et ne valide pas les maquettes.
Le premier lot de miroirs opérationnels (`7b30a00`, action `44500183345`)
**compile sans erreur**, mais son exécution de **108 XCTest présentait 7 échecs**,
liés aux références des articles restaurés avec un identifiant aléatoire.
Le correctif conserve désormais l'identifiant source ; son nouveau contrôle
macOS et le test de table réglée ont ensuite réussi : révision distante
**`2d7e912`**, action **`44501925643`**, job **`135483623881`** :
**build-for-testing réussi et 109/109 XCTest réussis, 0 échec**.
Cette validation couvre la fusion SwiftData en mémoire ; elle ne prouve pas
la disponibilité du CloudKit privé de production ou le partage entre comptes Apple.

L'audit suivant a ouvert **le véritable conteneur Apple** `iCloud.com.covi.app` :
les trois types COVI et leurs champs `payload: Bytes` ont été créés dans le
schéma **Development**. Le schéma **Production** ne comportait aucun type.
La prévisualisation du déploiement annonce trois nouveaux types et des
modifications aux rôles système ; le déploiement a été annulé avant toute
action sur la production. Le protocole détaillé de validation physique et de
partage inter-comptes est dans `native-ios/CLOUDKIT_VALIDATION.md`.
Le lancement de diagnostic suivant, **`4f037fe`**, action GitHub
**`44511213881`** (job `135515635113`), a **compilé sans erreur** et
**exécuté 113/113 XCTest, 0 échec**. Les nouveaux tests valident les deux
bases SwiftData de téléphones simulés, y compris les ventes concurrentes et
l'agenda hors-ligne ; les deux vrais iPhone demeurent nécessaires.

Après l'autorisation de préparer un TestFlight interne, le workflow manuel
`.github/workflows/ios-testflight.yml` a été redirigé vers le projet **natif**
`native-ios/COVI.xcodeproj` (schéma `COVI`). Le mode sans envoi vérifie les
secrets existants, les entitlements du profil de distribution, le projet
généré et les XCTest. Le mode signé est conditionné à une sélection explicite
et contrôle le Bundle ID `com.covi.app`, la version, la signature et l'accès
au CloudKit Production avant transmission. La syntaxe YAML et des 11 scripts
Bash a été vérifiée localement ; **le workflow n'a pas encore été exécuté sur
macOS**, le profil de signature n'est pas encore certifié compatible, et
aucune archive n'a été transmise à Apple.

Le préflight GitHub Actions **`44516821945`** (job `135534878731`) a ensuite
confirmé que la branche et tous les secrets configurés étaient disponibles.
Le profil existant porte le bon Team ID, le Bundle ID `com.covi.app` et
`Sign in with Apple`, mais **aucun des trois droits CloudKit requis**
(identifiant de conteneur, service et environnement `Production`). Le workflow
s'est interrompu avant la compilation et avant tout envoi, conformément aux
protections. Le profil ne sera pas recréé ni modifié par cet agent.

L'inspection du diff **avant** déploiement CloudKit Production a montré que
les trois nouveaux record types recevraient en base **publique** les droits
`GRANT READ TO "_world"`, `GRANT CREATE TO "_icloud"` et
`GRANT WRITE TO "_creator"`. Les zones privées actuellement utilisées par
COVI ne dépendent pas de ces droits publics, mais une publication telle quelle
permettrait de lire les éventuels enregistrements publics de ces types sans
authentification. **Déploiement suspendu** en attendant la confirmation précise
du retrait des droits publics de ces trois types ; le type `Users` préexistant
doit rester inchangé.

## Limites bloquantes

- Une connexion Apple et un compte iCloud ne prouvent **pas** à eux seuls la synchronisation complète :
  les nouveaux miroirs CloudKit exigent encore des essais réels sur deux appareils. Le stockage privé
  du propriétaire ne partage pas automatiquement les données avec le compte Apple d'un employé.
- Les anciens utilisateurs Supabase/Capacitor nécessitent un protocole de migration explicite.
- Les sources des 46 maquettes approuvées ne figurent pas dans ce checkout.
- Aucune archive iOS, aucun fichier de signature ni aucun profil de provisioning n'a été créé ou modifié.
- Aucun push n'a été effectué vers la branche reliée à Xcode Cloud.
