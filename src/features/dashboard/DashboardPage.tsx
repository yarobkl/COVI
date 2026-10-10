import { useCallback, useEffect, useState } from 'react'
import { CloudOffIcon, PlusIcon } from '../../components/icons'
import {
  Amount,
  Button,
  ButtonLink,
  EmptyState,
  Ledger,
  LedgerRow,
  Notice,
  Skeleton,
} from '../../components/ui'
import { useAsyncData } from '../../hooks/useAsyncData'
import { longDay, monthName } from '../../lib/dates'
import { fcfa, plural } from '../../lib/format'
import { pendingCount } from '../../lib/offline'
import { arrivalProfitability, dashboard, type ArrivalProfit } from '../../lib/operations'
import type { Shop } from '../../lib/types'
import { FirstDay } from './FirstDay'
import { LastSales } from './LastSales'
import { PaymentSplit } from './PaymentSplit'
import { ToFollow } from './ToFollow'

/**
 * Accueil: one hero figure (what the till received today), what to follow, the last sales and the
 * month in notebook lines.
 */
export function DashboardPage({ shop, onSimulation }: { shop: Shop; onSimulation: () => void }) {
  const load = useCallback(() => dashboard(shop.id), [shop.id])
  const { data: d, error, retry } = useAsyncData(load)
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

  if (!d)
    return (
      <div className="home">
        {head}
        <Skeleton caption="On fait les comptes…" />
      </div>
    )

  const firstDay =
    d.month.count === 0 &&
    d.recentSales.length === 0 &&
    d.stock === 0 &&
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
  const previous = d.previousMonth.total
  const previousName = monthName(d.previousMonth.date)

  return (
    <div className="home">
      {head}

      <section className="home-hero" aria-labelledby="home-today">
        {d.today.count > 0 ? (
          <>
            <h2 className="home-hero__lead" id="home-today">
              Aujourd’hui, la caisse a reçu
            </h2>
            <p className="amount amount--hero">
              {fcfa(d.today.total)}
              <span className="amount__unit">FCFA</span>
            </p>
            <p className="home-hero__count">
              en <strong>{plural(d.today.count, 'vente')}</strong> depuis ce matin.
            </p>
            <PaymentSplit parts={d.today.byMethod} />
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
          stock={d.stock}
        />

        <section className="home-grid__month home-month" aria-labelledby="home-month">
          <h2 className="section-title" id="home-month">
            {month.charAt(0).toUpperCase() + month.slice(1)}, jusqu’ici
          </h2>
          <Ledger>
            <LedgerRow
              variant="head"
              label={
                <>
                  Ventes <span className="muted">({d.month.count})</span>
                </>
              }
              value={<Amount value={d.month.total} />}
            />
            {d.month.expenses.map((e) => (
              <LedgerRow
                key={e.category}
                variant="sub"
                label={e.category}
                value={<Amount value={-e.amount} tone="out" regular />}
              />
            ))}
            <LedgerRow
              variant="total"
              label="Reste après charges"
              value={
                <Amount
                  value={d.month.restAfterCharges}
                  tone={d.month.restAfterCharges < 0 ? 'out' : undefined}
                />
              }
            />
          </Ledger>
          <p className="home-month__note">
            Sans compter ce que les articles vous ont coûté à l’achat.{' '}
            <a href="#/bilan">Voir ce que chaque arrivage a rapporté</a>
          </p>
          {previous > 0 && (
            <p className="hand home-month__hand">
              {d.month.total >= previous
                ? `déjà plus qu’en ${previousName} (${fcfa(previous)})`
                : `${previousName} avait fait ${fcfa(previous)} — encore ${fcfa(previous - d.month.total)} pour faire pareil`}
            </p>
          )}
        </section>

        <div className="home-grid__sales">
          <LastSales sales={d.recentSales} shop={shop} todayCount={d.today.count} />
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
