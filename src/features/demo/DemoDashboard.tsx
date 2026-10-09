import { money } from '../../lib/format'
import { arrivals, months } from './demoData'

/** Three-month overview; an arrival opens the "Mes arrivages" page on its detail. */
export function DemoDashboard({ onOpenArrival }: { onOpenArrival: (code: string) => void }) {
  return (
    <>
      <div className="demo-month-grid">
        {months.map((m) => (
          <article className="card" key={m.name}>
            <span>{m.name} 2026</span>
            <b>{money(m.sales)}</b>
            <small>
              Ventes encaissées · {m.buyers} clients · {m.units} articles
            </small>
            <small>{m.stock} produits disponibles en fin de mois</small>
          </article>
        ))}
      </div>
      <div className="demo-kpis">
        <article className="kpi">
          <span>Ventes encaissées</span>
          <b>{money(2334000)}</b>
          <small>sur trois mois</small>
        </article>
        <article className="kpi">
          <span>Investissements en arrivages</span>
          <b>{money(1230000)}</b>
          <small>3 arrivages reçus</small>
        </article>
        <article className="kpi">
          <span>Charges de la boutique</span>
          <b>{money(380000)}</b>
          <small>sur trois mois</small>
        </article>
        <article className="kpi">
          <span>Bénéfice final estimé</span>
          <b>{money(724000)}</b>
          <small>pilotage simulé, non comptable</small>
        </article>
      </div>
      <section className="card">
        <h2>Résultat de pilotage par mois</h2>
        <div className="demo-table-wrap">
          <table className="demo-table">
            <thead>
              <tr>
                <th>Mois</th>
                <th>Ventes</th>
                <th>Arrivages payés</th>
                <th>Charges</th>
                <th>Résultat du mois</th>
                <th>Stock disponible</th>
              </tr>
            </thead>
            <tbody>
              {months.map((m) => (
                <tr key={m.name}>
                  <td>{m.name} 2026</td>
                  <td>{money(m.sales)}</td>
                  <td>{money(m.arrivals)}</td>
                  <td>{money(m.expenses)}</td>
                  <td
                    className={
                      m.sales - m.arrivals - m.expenses < 0 ? 'demo-negative' : 'demo-profitable'
                    }
                  >
                    {money(m.sales - m.arrivals - m.expenses)}
                  </td>
                  <td>{m.stock} pièces</td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr>
                <th>Total</th>
                <th>{money(2334000)}</th>
                <th>{money(1230000)}</th>
                <th>{money(380000)}</th>
                <th>{money(724000)}</th>
                <th>12 pièces</th>
              </tr>
            </tfoot>
          </table>
        </div>
        <p className="demo-footnote">
          Calcul de pilotage de trésorerie : ventes encaissées − arrivages payés − charges. Les
          stocks restants ne sont pas valorisés dans ce résultat. Ce chiffre n’est pas une
          comptabilité officielle.
        </p>
      </section>
      <section className="card">
        <h2>Progression des arrivages</h2>
        <div className="demo-arrivals">
          {arrivals.map((a) => (
            <button
              className="demo-arrival-button"
              key={a.code}
              onClick={() => onOpenArrival(a.code)}
            >
              <span>
                <b>{a.code}</b>
                <small>
                  {a.origin} · {a.sold} vendus / {a.items}
                </small>
              </span>
              <span>
                <b>{money(a.revenue - a.cost)}</b>
                <small>{Math.round((a.revenue / a.cost) * 100)} % récupérés</small>
              </span>
            </button>
          ))}
        </div>
      </section>
    </>
  )
}
