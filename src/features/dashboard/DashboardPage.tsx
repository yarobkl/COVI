import { useCallback, useEffect, useState } from 'react'
import { CloudOffIcon, PlusIcon } from '../../components/icons'
import { Button, ButtonLink, EmptyState, Notice, Skeleton } from '../../components/ui'
import { useAsyncData } from '../../hooks/useAsyncData'
import { longDay, monthName } from '../../lib/dates'
import { fcfa, plural } from '../../lib/format'
import { pendingCount } from '../../lib/offline'
import {
  fetchEstimatedProfit,
  fetchShopDashboard,
  monthStartIn,
  type EstimatedProfit,
} from '../../lib/insights'
import { arrivalProfitability, dashboard, type ArrivalProfit } from '../../lib/operations'
import type { Shop } from '../../lib/types'
import { FirstDay } from './FirstDay'
import { LastSales } from './LastSales'
import { MonthLedger } from './MonthLedger'
import { PaymentSplit } from './PaymentSplit'
import { ToFollow } from './ToFollow'

/**
 * The home figures: the lists of dashboard() (last sales, low stock, arrivals on their way), the
 * month counted by the database (shop_dashboard, or the same calculation in the browser), and the
 * estimated profit when the database can compute it (null otherwise, or if it failed: the page
 * then keeps « Reste après charges »).
 */
async function loadHome(shopId: string) {
  const now = new Date()
  const lists = dashboard(shopId)
  const [d, figures, estimate] = await Promise.all([
    lists,
    fetchShopDashboard(shopId, {}, () => lists),
    fetchEstimatedProfit(shopId, {
      from: monthStartIn(now),
      to: monthStartIn(now, undefined, 1),
    }).catch((): EstimatedProfit | null => null),
  ])
  return { d, figures, estimate }
}

/**
 * Accueil: one hero figure (what the till received today), what to follow, the last sales and the
 * month in notebook lines.
 */
export function DashboardPage({ shop, onSimulation }: { shop: Shop; onSimulation: () => void }) {
  const load = useCallback(() => loadHome(shop.id), [shop.id])
  const { data, error, retry } = useAsyncData(load)
  // What each bale has brought back: optional, the page shows without it.
  const [profits, setProfits] = useState<ArrivalProfit[] | null>(null)
  useEffect(() => {
    let active = true
    arrivalProfitability(shop.id).then(
      (rows) => active && setProfits(rows),
      () => {},
    )
    return () => {
      active = false
    }
  }, [shop.id])

  const now = new Date()
  const head = (
    <header className="page-head home-head">
      <h1 className="home-date">{longDay(now)}</h1>
      <ButtonLink variant="sale" href="#/vendre" icon={<PlusIcon />} className="home-sale">
        Nouvelle vente
      </ButtonLink>
    </header>
  )

  if (error)
    return (
      <div className="home">
        {head}
        <Notice
          icon={CloudOffIcon}
          title="Les chiffres ne s’affichent pas : pas de réseau."
          actions={
            <Button variant="secondary" onClick={retry}>
              Réessayer
            </Button>
          }
        >
          <p>Vos ventes, elles, sont bien gardées.</p>
        </Notice>
      </div>
    )

  if (!data)
    return (
      <div className="home">
        {head}
        <Skeleton caption="On fait les comptes…" />
      </div>
    )

  const { d, figures, estimate } = data
  const firstDay =
    figures.saleCount === 0 &&
    d.recentSales.length === 0 &&
    figures.stock === 0 &&
    d.arrivalsInProgress.length === 0
  if (firstDay)
    return (
      <div className="home">
        {head}
        <FirstDay shopName={shop.name} onSimulation={onSimulation} />
      </div>
    )

  const balloons = (profits ?? []).filter(
    (a) => a.kind === 'balloon' && a.status === 'received' && !a.is_test && a.recovery < 100,
  )
  const pending = pendingCount()
  const month = monthName(now)
  const previous = figures.previousMonthSales
  const [py, pm] = figures.previousMonthStart.split('-').map(Number)
  const previousName = monthName(new Date(py, pm - 1, 1))

  return (
    <div className="home">
      {head}

      <section className="home-hero" aria-labelledby="home-today">
        {figures.todayCount > 0 ? (
          <>
            <h2 className="home-hero__lead" id="home-today">
              Aujourd’hui, la caisse a reçu
            </h2>
            <p className="amount amount--hero">
              {fcfa(figures.todaySales)}
              <span className="amount__unit">FCFA</span>
            </p>
            <p className="home-hero__count">
              en <strong>{plural(figures.todayCount, 'vente')}</strong> depuis ce matin.
            </p>
            <PaymentSplit parts={figures.todayByPaymentMethod} />
          </>
        ) : (
          <>
            <h2 className="visually-hidden" id="home-today">
              Aujourd’hui
            </h2>
            <EmptyState
              title="Pas encore de vente aujourd’hui."
              actions={
                <ButtonLink variant="sale" href="#/vendre">
                  Nouvelle vente
                </ButtonLink>
              }
            >
              <p>La première apparaîtra ici dès que vous l’aurez validée.</p>
            </EmptyState>
          </>
        )}
      </section>

      <div className="home-grid">
        <ToFollow
          className="home-grid__follow"
          balloons={balloons}
          lowStock={d.lowStock}
          arrivals={d.arrivalsInProgress}
          stock={figures.stock}
        />

        <section className="home-grid__month home-month" aria-labelledby="home-month">
          <h2 className="section-title" id="home-month">
            {month.charAt(0).toUpperCase() + month.slice(1)}, jusqu’ici
          </h2>
          <MonthLedger figures={figures} estimate={estimate} />
          {previous > 0 && (
            <p className="hand home-month__hand">
              {figures.monthSales >= previous
                ? `déjà plus qu’en ${previousName} (${fcfa(previous)})`
                : `${previousName} avait fait ${fcfa(previous)} — encore ${fcfa(previous - figures.monthSales)} pour faire pareil`}
            </p>
          )}
        </section>

        <div className="home-grid__sales">
          <LastSales sales={d.recentSales} shop={shop} todayCount={figures.todayCount} />
          {pending > 0 && (
            <Notice>
              <p>
                {pending > 1
                  ? `${pending} ventes gardées sur cet appareil, sans réseau, ne sont pas encore comptées ici. Elles s’ajouteront toutes seules : vous n’avez rien à faire.`
                  : '1 vente gardée sur cet appareil, sans réseau, n’est pas encore comptée ici. Elle s’ajoutera toute seule : vous n’avez rien à faire.'}
              </p>
            </Notice>
          )}
        </div>
      </div>
    </div>
  )
}
