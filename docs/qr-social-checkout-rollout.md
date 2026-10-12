# COVI — Caisse, QR et commandes sociales : état et mise en service

## Ce qui est développé sur la branche

- Caisse du commerçant : onglets **Vente au comptoir**, **Commandes reçues** et **QR & liens**.
- Panier par catégorie, quantité et prix de vente négocié, sans références SKU.
- Lien QR physique et lien réseaux sociaux permanents, désactivés par défaut.
- QR visuel **généré localement** avec `src/vendor/qrcode-generator.mjs` sous licence MIT.
- Formulaire visiteur sans compte : retrait ou livraison, téléphone pour livraison,
  commentaire, catégories et prix discutés ; aucun paiement dans ce formulaire.
- Demande reçue avec numéro à montrer au vendeur, sans faux reçu de paiement.
- File de demandes privée pour le propriétaire : prénom du client non requis,
  coordonnées facultatives, montants proposés et détail des catégories.
- Le propriétaire vérifie et approuve les prix avant d'ouvrir la confirmation.
- Encaissement manuel, prénom du vendeur inscrit sur la facture, puis vente et
  mouvement de stock atomiques, sans API Mobile Money.

## Points de sécurité

- `VITE_COVI_CATEGORY_CHECKOUT_ENABLED` vaut **faux par défaut**.
  Seul `true` active les nouveaux écrans dans une compilation de développement.
- L'ancien écran `#/vendre`, les connexions Google/Facebook et la production
  ne sont pas modifiés par cette activation tant que la branche n'est pas fusionnée.
- Le lien public permet **uniquement de déposer une demande** : jamais de
  confirmer la réception des fonds ni de modifier les stocks.
- La base ne publie que les noms et identifiants de catégories disponibles,
  sans quantités exactes, prix d'achat ou coordonnées des clients.
- Les fonctions d'approbation et d'encaissement exigent l'identité du
  **propriétaire authentifié** et vérifient l'appartenance à la boutique.
- Les demandes sont limitées en SQL à **60 nouvelles demandes par minute** et
  **1 000 par jour** par boutique. Un appel répété avec le même identifiant
  ne crée pas une seconde demande.
- Un propriétaire peut désactiver son lien ou le renouveler. Le renouvellement
  invalide **tous les anciens liens et QR codes imprimés**.
- Les brouillons SQL restent dans `supabase/sql-drafts/`, jamais
  dans `supabase/migrations/`.

## Ce qui reste bloquant avant d'activer la production

1. Auditer les RPC `SECURITY DEFINER`, les RLS et les rôles avec une
   instance Supabase complète, au-delà de la fixture PostgreSQL des tests.
2. Ajouter une protection réseau contre les abus (filtrage IP/WAF et,
   si nécessaire, CAPTCHA) ; les quotas SQL ne suffisent pas seuls.
3. Construire les droits des comptes employés/caissiers. Dans la version
   testée, seul le propriétaire connecté peut approuver et encaisser.
4. Permettre au vendeur de rectifier/rejeter un prix proposé avant
   approbation : actuellement il peut approuver ou laisser en attente.
5. Adapter les détails d'historique et statistiques aux ventes par catégorie.
6. Tester le parcours sur iPhone, Android et ordinateur, y compris le clavier,
   l'accessibilité, les impressions papier et la réduction des mouvements.
7. Ajouter un canal d'envoi sécurisé des photos/captures d'annonces
   sociales ; pour l'instant le client peut seulement écrire un commentaire.
8. Faire approuver explicitement les migrations et le déploiement par le
   propriétaire du projet.

## Tests

Le workflow `COVI isolated branch checks` exécute les vérifications
TypeScript, Vitest et PostgreSQL 17 jetable, y compris des ventes simultanées,
des refus de privilèges, les liens QR, les demandes anonymes, la limitation
de débit, la séparation du stock TEST et les retours réseau.

Le workflow Windows vérifie aussi le formatage Prettier, la compilation
et les tests web. L'installateur Windows ne se construit pas dans cette PR.

**Les résultats sur PostgreSQL isolé ne valent pas approbation de migration
en production.**
