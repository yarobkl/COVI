# COVI — Vérification de compatibilité avant « tout pousser »

**Date : 17 octobre 2026 — décision : PAS DE PUBLICATION GLOBALE.**

## Sources contrôlées

- Travail expérimental : `feature/covi-stock-central-omnichannel`, commit `aa49c0400445a54483894244a83b9da835c5701b`, pull request brouillon #22.
- `main` : commit `ffbc1c73f1acf01fa801094827ff1da13a615ef2`.
- Source Git de la production Vercel `covi-snowy.vercel.app` : **`claude/caisse-multi-caissiers`**, commit `ba8c99b7947686b22705aed3df1ab1ab6628c60a`. Vérifié par le déploiement Vercel `dpl_Ccb6w4zGdwsbpP7wfDcCju4NxJX3`, état `READY`, cible `production`.
- Comparaison GitHub : branche expérimentale **361 commits devant et 218 derrière** la branche réellement déployée. Comparée à `main` : **361 devant, 7 derrière**. Ces comptes datent du contrôle ; ils peuvent changer.
- GitHub Actions sur `aa49c04` : **trois workflows réussis** (Windows, branche isolée/PostgreSQL, Supabase natif). Cela confirme la santé de la branche de test, **pas sa compatibilité métier avec la production**.
- Migrations de la base actuelle : `shop_members`, `shared_cashier_profiles`, `public_order_channel`, `public_article_types_independent_stock`, `record_cart_sale`, `stock_movements_table`, `openpay_mobile_money` et d'autres sont déjà installées. En revanche, aucune des tables expérimentales `stock_categories`, `checkout_orders`, `checkout_order_lines`, `manual_payment_confirmations` n'existe actuellement.

## Éléments déjà présents en production

- `src/features/team/TillSwitch.tsx` : choix du caissier, PIN personnel, tenue du cahier de caisse ;
- `src/features/sale/SalePage.tsx` et `SaleForm.tsx` : vente par panier, prix négociés, protection contre les reprises réseau ;
- `src/features/orders/OrdersPage.tsx` / `PublicOrderPage.tsx` : commandes QR/WhatsApp/TikTok, suivi et captures des références ;
- Edge Function `public-checkout` : passerelle publique avec contrôles de provenance, quotas et Turnstile ;
- tables/RPC de ventes, produits et comptes déjà déployées.

**Conséquence :** merger la branche expérimentale dans `main` ou la promouvoir telle quelle vers Vercel introduirait une deuxième caisse et un deuxième modèle SQL, tout en risquant de supprimer des évolutions récentes. La simple réussite des tests GitHub n'autorise pas ce mélange.

## Stratégie sûre de mise en production

1. **Ne pas déployer/merger la PR #22 globalement.** Garder les brouillons SQL sous `supabase/sql-drafts/`, ne rien appliquer à Supabase.
2. Partir de **la branche qui alimente réellement la production**, pas d'une ancienne version de `main` : nouvelle branche d'intégration à partir de `claude/caisse-multi-caissiers`.
3. Faire la correspondance fonctionnalité par fonctionnalité : stock global et catégories, facture prénom/PIN, paiement reçu manuellement, QR/social, photos privées, rapports et journal des mouvements.
4. Reporter seulement les changements manquants, avec compatibilité additive des routes, de la DA « Le Cahier », de la base et des rôles. Éviter la création de doublons des RPC/tableaux existants.
5. Compléter l'audit de la sécurité publique (provenance réseau/IP, anti-abus), la rétention des données personnelles, les écarts de statistiques et la renégociation client avant encaissement.
6. Relancer **tests unitaires, formatage, lint, TypeScript, tests de concurrence PostgreSQL, tests Supabase Auth/PostgREST**, et recettes sur téléphone ; définir sauvegardes/retour arrière.
7. Faire une revue finale explicite avant toute migration additive, fusion vers la branche réellement déployée et promotion Vercel.

## Ce qui est autorisé maintenant

Commits sur la branche de développement et tests isolés. **Aucune activation de fonctionnalité, mutation Supabase, fusion vers `main` ou la branche production, ni promotion Vercel** dans cette étape de vérification.
