import { Amount, Ledger, LedgerRow } from '../../components/ui'
import { fcfa } from '../../lib/format'
import type { EstimatedProfit, ShopDashboard } from '../../lib/insights'

/**
 * The month in notebook lines. With the database's estimate: sales − what the goods sold cost −
 * charges = « Bénéfice estimé ». Without it (functions not there yet, or the estimate failed):
 * « Reste après charges », plainly marked as a provisional marker and never called a profit.
 */
export function MonthLedger({
  figures,
  estimate,
}: {
  figures: Pick<
    ShopDashboard,
    'monthSales' | 'saleCount' | 'expensesByCategory' | 'restAfterCharges'
  >
  estimate: EstimatedProfit | null
}) {
  const sales = (
    <LedgerRow
      variant="head"
      label={
        <>
          Ventes <span className="muted">({figures.saleCount})</span>
        </>
      }
      value={<Amount value={estimate ? estimate.revenue : figures.monthSales} />}
    />
  )
  const charges = figures.expensesByCategory.map((e) => (
    <LedgerRow
      key={e.category}
      variant="sub"
      label={e.category}
      value={<Amount value={-e.amount} tone="out" regular />}
    />
  ))

  if (estimate)
    return (
      <>
        <Ledger>
          {sales}
          <LedgerRow
            variant="sub"
            label="Coût des articles vendus"
            value={<Amount value={-estimate.costOfGoodsSold} tone="out" regular />}
          />
          {charges}
          <LedgerRow
            variant="total"
            label="Bénéfice estimé"
            value={
              <Amount
                value={estimate.netProfit}
                tone={estimate.netProfit < 0 ? 'out' : undefined}
              />
            }
          />
        </Ledger>
        <p className="home-month__note">
          Ventes − coût des articles vendus − charges. Le prix d’un arrivage est réparti sur ses
          articles ; pour un ballon : son prix ÷ les pièces enregistrées.
          {estimate.revenueWithoutCost > 0 &&
            ` ${fcfa(estimate.revenueWithoutCost)}\u00a0FCFA de ventes d’articles sans arrivage sont comptées sans coût.`}{' '}
          <a href="#/bilan">Voir ce que chaque arrivage a rapporté</a>
        </p>
      </>
    )

  return (
    <>
      <Ledger>
        {sales}
        {charges}
        <LedgerRow
          variant="total"
          label="Reste après charges"
          value={
            <Amount
              value={figures.restAfterCharges}
              tone={figures.restAfterCharges < 0 ? 'out' : undefined}
            />
          }
        />
      </Ledger>
      <p className="home-month__note">
        <strong>Repère provisoire.</strong> Sans compter ce que les articles vous ont coûté à
        l’achat. <a href="#/bilan">Voir ce que chaque arrivage a rapporté</a>
      </p>
    </>
  )
}
