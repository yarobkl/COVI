# COVI — Registre partagé des anomalies métier (GPT)
Dernière revue : 24 octobre 2026. **Seules les observations contrôlées en code sont qualifiées ; les cas non exécutés sont signalés à part.** Claude conserve la propriété des corrections techniques.

| Réf. | Priorité | Domaine | Constats et reproduction | Responsable technique | Décision / statut |
| --- | --- | --- | --- | --- | --- |
| ANO-FIN-001 | P0 | Salon / rapports | Voir `salon_report` (PR #64) : facturer 12 000 FCFA le 28 septembre, rembourser le 5 octobre, puis consulter le rapport de septembre et celui d'octobre. La clause `l.refunded_at is null` supprime potentiellement la vente du CA de septembre rétrospectivement. Le rapport d'octobre enregistre le décaissement mais ne rattache pas explicitement l'ajustement de CA à octobre. | CLA-05 (règle), CLA-02 (SQL/migration) | **Décision propriétaire requise** sur FIN-004 ; test réel non exécuté |
| ANO-QA-001 | P0 | Préproduction / accès | Le connecteur ChatGPT ne voit pas `stcsjwxmmxnjwisqkudz` : refus d'autorisation, puis `link_id must identify an eligible linked account`. La présence réelle des migrations est inconnue côté GPT. | CLA-02 fournit des preuves, aucune modification de connexion requise pour poursuivre | **Limitation d'observation**, pas un défaut prouvé dans Supabase |
| ANO-UX-001 | P1 | Salon / hors ligne | Simuler paiement reçu par le serveur mais réponse perdue au client ; le texte générique de `salonErrorMessage` annonce « rien n'a été enregistré ». Vérifier affichage de l'état réel et réutilisation de la même clé d'opération avant une nouvelle tentative. | CLA-05 / CLA-07 | **Risque à reproduire**, correction non présumée nécessaire sans preuve |

## Anomalies historiques vérifiées comme corrigées en code
- `SalonCheckoutPage.tsx` : `onChanged={data.reload}` présent sur la branche PR #64 ; exécution E2E restant à valider.
- `SalonReportsPage.tsx` : fuseau `time_zone` chargé depuis `salonApi.settings` ; tests multizones restant à valider.

Pour clôturer un ticket : joindre une preuve reproductible (version, référence du scénario, attente/observation, résultat serveur), faire corriger par Claude, puis obtenir une contre-vérification GPT-06.
