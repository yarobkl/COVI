import { useCallback, useMemo, useState } from 'react'
import { CloudOffIcon } from '../../components/icons'
import { Button, EmptyState, Ledger, LedgerRow, Notice, Skeleton } from '../../components/ui'
import { Switch } from '../../components/ui/Switch'
import { useAsyncData } from '../../hooks/useAsyncData'
import { fcfa, plural } from '../../lib/format'
import { liveStatistics } from '../../lib/operations'
import '../../styles/app/bilan.css'
import { ArrivalResults } from './ArrivalResults'
import {
  arrivalResults,
  bilanTotal,
  hasExamples,
  lastMonths,
  monthlyBilan,
  topCategories,
} from './bilanMath'
import { MonthBars } from './MonthBars'
import { MonthTable } from './MonthTable'

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1)

/**
 * Bilan: the last three months (sales, charges, what is left), what sells best, and what each
 * arrival brought back. Example data is left out unless the seller switches it on.
 */
export function StatisticsPage({ shopId }: { shopId: string }) {
  const [now] = useState(() => new Date())
  const load = useCallback(() => liveStatistics(shopId, now), [shopId, now])
  const { data, error, retry } = useAsyncData(load)
  const [withExamples, setWithExamples] = useState(false)
  const months = useMemo(() => lastMonths(now), [now])

  const head = (
    <header className="page-head">
      <div>
        <h1>Bilan</h1>
        <p className="page-head__sub">Les 3 derniers mois, et ce que chaque arrivage a rapporté.</p>
      </div>
    </header>
  )

  if (error)
    return (
      <div className="bilan">
        {head}
        <Notice
          icon={CloudOffIcon}
          title="Le bilan ne s’affiche pas : pas de réseau."
          actions={
            <Button variant="secondary" onClick={retry}>
              Réessayer
            </Button>
          }
        >
          <p>Réessayez dans un instant.</p>
        </Notice>
      </div>
    )
  if (!data)
    return (
      <div className="bilan">
        {head}
        <Skeleton caption="On fait les comptes…" />
      </div>
    )

  const examples = hasExamples(data)
  const include = examples && withExamples
  const bilan = monthlyBilan(data, months, include)
  const total = bilanTotal(bilan)
  const categories = topCategories(data.sales, months, include)
  const arrivals = arrivalResults(data.profit, include)
  const period = `${capitalize(months[0].label)} à ${months[months.length - 1].label}`

  return (
    <div className="bilan">
      {head}

      {examples && (
        <div className="bilan__examples">
          <Switch checked={withExamples} onChange={setWithExamples}>
            Inclure la boutique d’exemple
          </Switch>
          <p className="muted">
            {withExamples
              ? 'Les chiffres comptent aussi les ventes, charges et arrivages « Exemple ».'
              : 'Les ventes, charges et arrivages « Exemple » ne sont pas comptés.'}
          </p>
        </div>
      )}

      <section className="bilan-hero" aria-labelledby="bilan-hero">
        <h2 className="bilan-hero__lead" id="bilan-hero">
          {period}, la caisse a reçu
        </h2>
        <p className="amount amount--hero">
          {fcfa(total.sales)}
          <span className="amount__unit">FCFA</span>
        </p>
        <p className="bilan-hero__count">
          en <strong>{plural(total.count, 'vente')}</strong>.
        </p>
      </section>

      <div className="bilan-grid">
        <section className="bilan-months" aria-labelledby="bilan-months">
          <h2 className="section-title" id="bilan-months">
            Ventes par mois
          </h2>
          <MonthBars months={bilan.map((m) => ({ key: m.key, label: m.label, amount: m.sales }))} />
          <MonthTable months={bilan} total={total} />
          <p className="bilan-note">
            <strong>Reste après charges</strong> = ventes encaissées − charges du mois. Ce que vous
            avez payé pour la marchandise n’est pas retiré : voyez plus bas ce que chaque arrivage a
            rapporté. C’est un repère pour vous, pas une comptabilité officielle.
          </p>
        </section>

        <section className="bilan-categories" aria-labelledby="bilan-categories">
          <h2 className="section-title" id="bilan-categories">
            Ce qui part le mieux
          </h2>
          {categories.length === 0 ? (
            <p className="muted">Après quelques ventes, vous verrez ici ce qui part le mieux.</p>
          ) : (
            <Ledger>
              {categories.map((c) => (
                <LedgerRow
                  key={c.category}
                  label={c.category}
                  value={
                    <span className="bilan-categories__count">
                      <span className="figures">{c.pieces}</span>{' '}
                      {c.pieces > 1 ? 'pièces vendues' : 'pièce vendue'}
                    </span>
                  }
                />
              ))}
            </Ledger>
          )}
        </section>
      </div>

      <section className="bilan-arrivals" aria-labelledby="bilan-arrivals">
        <h2 className="section-title" id="bilan-arrivals">
          Ce que chaque arrivage a rapporté
        </h2>
        {arrivals.shown.length === 0 ? (
          <EmptyState title="Pas encore d’arrivage à comparer.">
            <p>
              Notez vos ballons et vos commandes dans <a href="#/arrivages">Arrivages</a> : vous
              verrez ici ce que chacun vous rapporte.
            </p>
          </EmptyState>
        ) : (
          <ArrivalResults arrivals={arrivals.shown} />
        )}
        {arrivals.notReceived > 0 && (
          <p className="muted">
            {arrivals.notReceived > 1
              ? `${arrivals.notReceived} arrivages pas encore reçus ne sont pas comptés ici.`
              : '1 arrivage pas encore reçu n’est pas compté ici.'}{' '}
            <a href="#/arrivages">Voir les arrivages</a>
          </p>
        )}
      </section>
    </div>
  )
}
