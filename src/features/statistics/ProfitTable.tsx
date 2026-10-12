import { Amount } from '../../components/ui'
import type { EstimatedProfit } from '../../lib/insights'
import '../../styles/app/bilan.css'

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

/** Month by month, as the database estimates it: what the goods sold cost, and what is left. */
export function ProfitTable({
  months,
}: {
  months: { key: string; label: string; estimate: EstimatedProfit }[]
}) {
  const total = months.reduce(
    (t, m) => ({
      cost: t.cost + m.estimate.costOfGoodsSold,
      net: t.net + m.estimate.netProfit,
    }),
    { cost: 0, net: 0 },
  )
  return (
    <table className="bilan-table">
      <caption className="visually-hidden">
        Coût des articles vendus et bénéfice estimé, par mois
      </caption>
      <thead>
        <tr>
          <th scope="col">Mois</th>
          <th scope="col">
            Coût des articles <span className="bilan-table__long">vendus</span>
          </th>
          <th scope="col">Bénéfice estimé</th>
        </tr>
      </thead>
      <tbody>
        {months.map((m) => (
          <tr key={m.key}>
            <th scope="row">{capitalize(m.label)}</th>
            <td>
              <Amount
                value={-m.estimate.costOfGoodsSold}
                tone={m.estimate.costOfGoodsSold > 0 ? 'out' : undefined}
                regular
              />
            </td>
            <td>
              <Amount
                value={m.estimate.netProfit}
                tone={m.estimate.netProfit < 0 ? 'out' : undefined}
              />
            </td>
          </tr>
        ))}
      </tbody>
      <tfoot>
        <tr>
          <th scope="row">Total</th>
          <td>
            <Amount value={-total.cost} tone={total.cost > 0 ? 'out' : undefined} />
          </td>
          <td>
            <Amount value={total.net} tone={total.net < 0 ? 'out' : undefined} />
          </td>
        </tr>
      </tfoot>
    </table>
  )
}
