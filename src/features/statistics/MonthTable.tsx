import { Amount } from '../../components/ui'
import '../../styles/app/bilan.css'
import type { BilanMonth } from './bilanMath'

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

/** The months in a real table: sales, charges and what is left after charges. */
export function MonthTable({
  months,
  total,
}: {
  months: BilanMonth[]
  total: Pick<BilanMonth, 'sales' | 'charges' | 'rest'>
}) {
  return (
    <table className="bilan-table">
      <caption className="visually-hidden">
        Ventes, charges et reste après charges, par mois
      </caption>
      <thead>
        <tr>
          <th scope="col">Mois</th>
          <th scope="col">Ventes</th>
          <th scope="col">Charges</th>
          <th scope="col">
            Reste <span className="bilan-table__long">après charges</span>
          </th>
        </tr>
      </thead>
      <tbody>
        {months.map((m) => (
          <tr key={m.key}>
            <th scope="row">{capitalize(m.label)}</th>
            <td>
              <Amount value={m.sales} regular />
            </td>
            <td>
              <Amount value={-m.charges} tone={m.charges > 0 ? 'out' : undefined} regular />
            </td>
            <td>
              <Amount value={m.rest} tone={m.rest < 0 ? 'out' : undefined} />
            </td>
          </tr>
        ))}
      </tbody>
      <tfoot>
        <tr>
          <th scope="row">Total</th>
          <td>
            <Amount value={total.sales} />
          </td>
          <td>
            <Amount value={-total.charges} tone={total.charges > 0 ? 'out' : undefined} />
          </td>
          <td>
            <Amount value={total.rest} tone={total.rest < 0 ? 'out' : undefined} />
          </td>
        </tr>
      </tfoot>
    </table>
  )
}
