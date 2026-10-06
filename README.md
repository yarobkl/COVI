# COVI

**COVI — Le système d’exploitation de votre commerce.**

COVI est un outil de pilotage simple pour les petits commerces africains. Il relie les arrivages, le stock, les ventes, les charges et la rentabilité sans exposer la complexité d’un ERP traditionnel.

## Parcours métier V1

`ARRIVAGE → COMMANDE FOURNISSEUR / BALLON → PRODUITS → STOCK → VENTE → HISTORIQUE → BÉNÉFICE → STATISTIQUES`

### Fonctionnel aujourd’hui

- Authentification et création du commerce
- Stock réel, quantités et pièces uniques
- Commandes fournisseurs et ballons / lots mixtes
- Pays d’origine recherchable
- Cycle brouillon → commandé → en transit → reçu
- Ajout de références fournisseur avec quantité
- Découverte progressive des pièces d’un ballon
- Vente avec prix initial, prix réellement vendu et moyen de paiement
- Décrémentation atomique du stock
- Historique des produits vendus
- Charges de la boutique
- Rentabilité par arrivage et récupération de l’investissement
- Dashboard et statistiques sur données réelles
- Cache local du stock
- File de ventes hors connexion, reprise automatique et anti-doublon
- État de synchronisation visible
- Paramètres du commerce
- Application desktop Tauri
- Build automatisé d’un installateur Windows NSIS

## Stack

React · TypeScript · Vite · Supabase/PostgreSQL · Tauri · GitHub Actions · Vercel

## Développement

```bash
npm ci
npm run dev
npm run build
npm run tauri build
```

Le pipeline `COVI Windows` compile d’abord le front puis construit l’installateur Windows sur un runner Windows. Une modification qui ne compile pas ne produit pas d’installateur.

## Principes produit

- Puissant derrière. Extrêmement simple devant.
- Vocabulaire métier, pas jargon ERP.
- Les ballons gardent un coût global : COVI n’invente pas un coût d’achat par pièce.
- Les produits vendus restent dans l’historique.
- Les charges de fonctionnement restent séparées du coût des arrivages.
- Le bénéfice affiché est une estimation de pilotage, pas une comptabilité officielle.

## Prochaines couches

Photos produits, synchronisation offline étendue aux écritures autres que les ventes, expérience mobile dédiée, permissions employés, multi-boutiques et distribution Windows signée.
