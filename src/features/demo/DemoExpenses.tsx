import { money } from '../../lib/format'
import { monthlyExpenses } from './demoData'

export function DemoExpenses() {
  return (
    <section className="card">
      <h2>Charges de la boutique</h2>
      <p>Simulation des charges ponctuelles et récurrentes sur la période.</p>
      <div className="demo-table-wrap">
        <table className="demo-table">
          <thead>
            <tr>
              <th>Mois</th>
              <th>Loyer</th>
              <th>Autres charges</th>
              <th>Total</th>
            </tr>
          </thead>
          <tbody>
            {monthlyExpenses.map(([month, rent, other, total]) => (
              <tr key={month}>
                <td>{month}</td>
                <td>{money(rent)}</td>
                <td>{money(other)}</td>
                <td>{money(total)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}
