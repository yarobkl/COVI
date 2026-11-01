import type { SalonReport } from '../../lib/salon'
import { methodLabels } from './salonFormat'

/** Lignes du fichier CSV d'un rapport (séparateur « ; », ouvert par Excel en français). */
export function reportCsvRows(r: SalonReport): unknown[][] {
  const f = r.finance
  return [
    ['Rapport du salon', `${r.period.from} au ${r.period.to}`],
    [],
    ['Indicateur', 'Montant (FCFA)'],
    ['Prestations réalisées et payées', f.services_revenue_xaf],
    ['Ventes de produits', f.products_revenue_xaf],
    ['Chiffre d’affaires réalisé', f.revenue_xaf],
    ['Consommables et coûts directs des prestations', f.service_direct_costs_xaf],
    ['Coût d’achat des produits vendus', f.product_costs_xaf],
    ['Commissions dues', f.commissions_due_xaf],
    ['Autres charges saisies (hors commissions)', f.other_charges_xaf],
    ['Résultat de pilotage estimé', f.estimated_result_xaf],
    ['Paiements reçus', f.payments_xaf],
    ['Remboursements versés', f.refunds_xaf],
    ['Encaissements nets', f.net_collected_xaf],
    ['Commissions versées', f.commissions_paid_xaf],
    ['Achats de produits', f.purchases_xaf],
    ['Flux de trésorerie estimé', f.estimated_cash_flow_xaf],
    ['En attente d’encaissement (non compté)', f.pending_checkout_xaf],
    [],
    ['Prestation', 'Nombre', 'CA', 'Marge après coûts et commissions'],
    ...r.services.map((s) => [s.name, s.count, s.revenue_xaf, s.margin_xaf]),
    [],
    ['Collaborateur', 'Prestations', 'CA', 'Commission'],
    ...r.staff.map((s) => [s.full_name, s.services, s.revenue_xaf, s.commission_xaf]),
    [],
    ['Moyen de paiement', 'Reçu', 'Remboursé', 'Net'],
    ...r.payment_methods.map((m) => [
      methodLabels[m.method],
      m.payments_xaf,
      m.refunds_xaf,
      m.net_xaf,
    ]),
    [],
    ['Jour', 'CA'],
    ...r.daily.map((d) => [d.day, d.revenue_xaf]),
  ]
}
