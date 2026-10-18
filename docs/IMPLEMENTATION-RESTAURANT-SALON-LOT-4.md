# COVI — Lot 4 : panier collectif Restaurant multi-téléphones

Date : 17 octobre 2026  
Branche : `feature/covi-restaurant-salon-v1` — PR brouillon n°44  
Statut : développements de branche, **pas de migration Supabase ni de déploiement**.

## Réalisé

- **Accès indépendant de chaque restaurant** : le QR imprimé identifie uniquement la table, sans pouvoir ouvrir un nouveau groupe sans autorisation. Le propriétaire ouvre la session et génère un code de groupe de 8 caractères, temporaire et renouvelable.
- **Admission en groupe** : chaque convive scanne le QR, saisit le code donné par le personnel, passe le contrôle anti-robot Turnstile, et obtient un jeton propre à son téléphone. Le secret invité est conservé uniquement sous forme d'empreinte SHA-256 dans PostgreSQL. Les codes sont spécifiques à la session, jamais partagés entre commerces.
- **Participants et capacité distincts** : la table peut avoir quatre places et seulement deux clients déclarés. Le nombre de participants admis ne dépasse pas ce nombre déclaré; un téléphone peut composer le panier de plusieurs convives.
- **Choix simultanés** : chaque invité enregistre et modifie ses propres articles; les modifications se font dans une transaction SQL sérialisée par session, sans effacer les choix des autres appareils. Tarifs et disponibilités proviennent exclusivement du restaurant en base.
- **Responsable automatique** : le premier invité à appuyer sur « J'ai terminé mon choix » est désigné responsable de façon atomique. Aucun envoi ne part automatiquement quand les participants sont prêts.
- **Validation finale** : le responsable, et lui seul, appuie sur « Envoyer la commande du groupe » quand les participants déclarés dans le panier ont terminé. Référence `CMD-...` unique par établissement; deuxième clic ou reprise après perte réseau renvoie la même commande.
- **Stock des boissons** : soumission via le même cœur serveur que la caisse propriétaire. Réservation des quantités atomique, refus si stock insuffisant. Aucune déduction de stock fictive avant service.
- **Suivi** : après soumission, chaque participant peut retrouver la même référence et le récapitulatif. L'accès de l'ancien groupe expire après clôture du paiement.
- **Protection du public** : Edge Function `restaurant-guest` séparée de `public-checkout` pour les vêtements. Vérification de l'origine, action Cloudflare Turnstile pour admission, contrôle de taille/forme, fonctions privées réservées à `service_role`, empreintes HMAC et quotas durables en base contre les essais de code.
- **UI** : le QR restaurant affiche le panier collectif uniquement quand la variable `VITE_COVI_RESTAURANT_GUEST_ENABLED=true` est définie; l'Edge refuse également tout si `COVI_RESTAURANT_GUEST_ENABLED` n'est pas `true`. La double activation est désactivée par défaut.

## Vérifications exécutées en base PostgreSQL jetable

- Deux appareils sur une table 4 places, 2 convives déclarés; choix distincts persistés dans une seule session.
- Le troisième appareil est refusé lorsque le nombre de participants déclarés est atteint; un code incorrect est refusé.
- Un article d'un autre restaurant ou un QR d'un autre établissement ne permet aucun ajout.
- Un seul responsable, et non le deuxième convive, peut envoyer le groupe. Validation prématurée bloquée tant qu'un membre déjà admis n'a pas terminé.
- Deux validations du responsable produisent la même référence; paiement complet libère la table; jeton de l'ancienne session révoqué.
- Lecture du numéro de commande après une coupure réseau simulée.
- Quotas limitant les tentatives et refus de l'exécution directe des RPC invitées par `anon` ou `authenticated`.

## Restant et conditions de mise en ligne

1. **Employés** : comptes distincts et permissions serveur par restaurant pour serveuses, cuisiniers, caissières; traçabilité nominative et accès complet uniquement au propriétaire. La caisse Restaurant actuelle fonctionne en mode propriétaire de test.
2. **Code d'admission** : processus réel d'accueil, renouvellement si le responsable quitte la table, participants sans smartphone, demandes de correction après envoi.
3. **Montée en charge et réseaux** : tests e2e multi-téléphones réels, interruptions 3G/Wi‑Fi, latence, clics simultanés, gestion des menus modifiés pendant le panier, attaques automatiques et disponibilité des serveurs.
4. **Paiements** : espèces attestées par employé habilité, Mobile Money seulement après preuve du fournisseur, remboursements/annulations, rapprochement systématique.
5. **Salon** : formulaire public de RDV et QR partageable restent hors ligne jusqu'à la protection anti-abus, le contrôle des horaires et la validation du salon.
6. **Finances** : export Excel/PDF, paie et bilans fiables à réconcilier; ne jamais présenter les totaux partiels de tableau de bord comme bénéfices certains.
7. **Sécurité** : revue finale Supabase RLS/RPC/Edge, journalisation, rotation des clés et revue des secrets. Ne jamais communiquer un code temporaire sur un lien public ou l'imprimer avec le QR permanent.
8. **Activation** : Vercel, Supabase et migrations inchangés jusqu'à autorisation explicite. Les variables d'activation sont absentes / désactivées dans la production.

**Aucun GO de production à ce stade.** Préserver la DA « Le Cahier » et les opérations des boutiques de vêtements.
