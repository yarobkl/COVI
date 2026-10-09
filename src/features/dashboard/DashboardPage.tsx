import { useEffect, useState } from 'react'
import { money } from '../../lib/format'
import { dashboard } from '../../lib/operations'
import { Kpi } from './Kpi'

type Dashboard = Awaited<ReturnType<typeof dashboard>>

export function DashboardPage({ shopId }: { shopId: string }) {
  const [d, setD] = useState<Dashboard | null>(null)
  useEffect(() => {
    dashboard(shopId).then(setD)
  }, [shopId])
  if (!d) return <p>Chargement du commerce…</p>
  return (
    <div>
      <div className="hello">
        <div>
          <h1>Tableau de bord</h1>
          <span>Voici l'essentiel réel de votre commerce.</span>
        </div>
      </div>
      <div className="kpis">
        <Kpi t="Ventes aujourd’hui" v={money(d.todaySales)} s="encaissées" />
        <Kpi t="Ventes ce mois" v={money(d.monthSales)} s={d.saleCount + ' ventes'} />
        <Kpi t="Bénéfice final estimé" v={money(d.profit)} s="Après arrivages et charges" />
        <Kpi t="Stock disponible" v={String(d.stock)} s="articles" />
      </div>
      <div className="grid">
        <section className="card">
          <small>RÉSULTAT DU MOIS</small>
          <h2>{money(d.profit)}</h2>
          <div className="profit">
            <span>
              Ventes encaissées <b>{money(d.monthSales)}</b>
            </span>
            <span>
              Coût des arrivages <b>- {money(d.arrivalCost)}</b>
            </span>
            <span>
              Bénéfice avant charges <b>{money(d.profitBeforeCharges)}</b>
            </span>
            <span>
              Charges de la boutique <b>- {money(d.charges)}</b>
            </span>
          </div>
        </section>
        <section className="card">
          <small>PILOTAGE</small>
          <h2>Votre commerce en direct</h2>
          <div className="profit">
            <span>
              Arrivages en cours <b>{d.arrivalsInProgress}</b>
            </span>
            <span>
              Commandes fournisseurs <b>{d.ordersInProgress}</b>
            </span>
            <span>
              Ballons en cours <b>{d.balloonsInProgress}</b>
            </span>
          </div>
        </section>
      </div>
    </div>
  )
}
