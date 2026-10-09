import { money } from '../../lib/format'

export function DemoStatistics() {
  return (
    <section className="card">
      <h2>Statistiques des trois mois</h2>
      <div className="demo-kpis">
        {[
          ['Tickets clients', '105'],
          ['Articles vendus', '143'],
          ['Ventes encaissées', money(2334000)],
          ['Stock restant', '12 articles'],
        ].map(([label, value]) => (
          <div className="kpi" key={label}>
            <span>{label}</span>
            <b>{value}</b>
          </div>
        ))}
      </div>
      <h3>Articles les plus vendus</h3>
      <ol className="demo-ranking">
        <li>
          Article modèle D <b>35 vendus</b>
        </li>
        <li>
          Chemise modèle C <b>28 vendues</b>
        </li>
        <li>
          Robe modèle A <b>20 vendues</b>
        </li>
      </ol>
    </section>
  )
}
