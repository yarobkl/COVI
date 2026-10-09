import { money } from '../../lib/format'
import { arrivals } from './demoData'

/** Simulated arrivals; clicking one toggles its detail. */
export function DemoArrivals({
  selectedArrival,
  onSelectArrival,
}: {
  selectedArrival: string | null
  onSelectArrival: (code: string | null) => void
}) {
  return (
    <section className="card">
      <h2>Arrivages et rentabilité</h2>
      <div className="demo-arrivals">
        {arrivals.map((a) => (
          <article key={a.code}>
            <button
              className="demo-arrival-button"
              onClick={() => onSelectArrival(selectedArrival === a.code ? null : a.code)}
            >
              <span>
                <b>
                  {a.code} · {a.kind}
                </b>
                <small>
                  {a.origin} · Reçu le {a.received}
                </small>
              </span>
              <span>
                <b>{money(a.revenue - a.cost)}</b>
                <small>{Math.round((a.revenue / a.cost) * 100)} % récupérés</small>
              </span>
            </button>
            {selectedArrival === a.code && (
              <div className="demo-arrival-detail">
                <span>{a.supplier}</span>
                <span>
                  {a.items} enregistrés · {a.sold} vendus · {a.remaining} restants
                </span>
                <span>
                  Coût {money(a.cost)} · Ventes {money(a.revenue)}
                </span>
                {a.code === 'BAL-001' && <b className="demo-profitable">BALLON RENTABILISÉ</b>}
              </div>
            )}
          </article>
        ))}
      </div>
    </section>
  )
}
