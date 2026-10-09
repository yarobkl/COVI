import { money } from '../../lib/format'
import { remainingStock } from './demoData'

export function DemoStock() {
  return (
    <section className="card">
      <h2>Stock au 30 septembre</h2>
      <p>12 produits enregistrés encore disponibles dans cette simulation.</p>
      <div className="demo-table-wrap">
        <table className="demo-table">
          <thead>
            <tr>
              <th>Produit</th>
              <th>Arrivage</th>
              <th>Qté restante</th>
              <th>Prix de vente</th>
            </tr>
          </thead>
          <tbody>
            {remainingStock.map((row) => (
              <tr key={row[1] + '-' + row[0]}>
                <td>{row[0]}</td>
                <td>{row[1]}</td>
                <td>{row[2]}</td>
                <td>{money(Number(row[3]))}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  )
}
