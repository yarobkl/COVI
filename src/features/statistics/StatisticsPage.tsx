import { useEffect, useState } from 'react'
import { money } from '../../lib/format'
import { liveStatistics } from '../../lib/operations'
import { ArrivalProfitRow } from './ArrivalProfitRow'

type Statistics = Awaited<ReturnType<typeof liveStatistics>>

export function StatisticsPage({ shopId }: { shopId: string }) {
  const [d, setD] = useState<Statistics | null>(null)
  useEffect(() => {
    void liveStatistics(shopId).then(setD)
  }, [shopId])
  if (!d) return <p>Calcul des statistiques…</p>
  const max = Math.max(1, ...d.days.map((x) => x.amount))
  return (
    <div>
      <div className="hello">
        <div>
          <h1>Statistiques</h1>
          <span>Vos performances réelles et les arrivages de simulation identifiés TEST.</span>
        </div>
      </div>
      <div className="grid">
        <section className="card">
          <small>VENTES · 3 DERNIERS MOIS COMPLETS · TEST INCLUS ET SIGNALÉ</small>
          <div className="bars">
            {d.days.map((x) => (
              <div className="barcol" key={x.date}>
                <div className="bar" style={{ height: Math.max(4, (x.amount / max) * 150) }}></div>
                <span>{x.label}</span>
                <small>{x.amount ? money(x.amount) : '0'}</small>
              </div>
            ))}
          </div>
        </section>
        <section className="card">
          <small>CATÉGORIES VENDUES</small>
          {d.categories.length === 0 ? (
            <p>Les catégories apparaîtront après vos premières ventes.</p>
          ) : (
            d.categories.map(([category, count]) => (
              <div className="statline" key={category}>
                <span>{category}</span>
                <b>
                  {count} vendu{count > 1 ? 's' : ''}
                </b>
              </div>
            ))
          )}
        </section>
      </div>
      <section className="card">
        <small>RENTABILITÉ DES ARRIVAGES</small>
        {d.profit.length === 0 ? (
          <p>Aucun arrivage à analyser.</p>
        ) : (
          d.profit.map((x) => <ArrivalProfitRow key={x.id} arrival={x} />)
        )}
      </section>
    </div>
  )
}
