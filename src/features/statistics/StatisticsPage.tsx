import { useCallback } from 'react'
import { LoadError } from '../../components/LoadError'
import { Ledger, LedgerRow, PageHead, Sheet, Skeleton } from '../../components/ui'
import { useAsyncData } from '../../hooks/useAsyncData'
import { fcfa, money, plural } from '../../lib/format'
import { liveStatistics } from '../../lib/operations'
import { ArrivalProfitRow } from './ArrivalProfitRow'

export function StatisticsPage({ shopId }: { shopId: string }) {
  const load = useCallback(() => liveStatistics(shopId), [shopId])
  const { data: d, error, retry } = useAsyncData(load)
  if (error)
    return (
      <LoadError
        message="Impossible de calculer les statistiques. Vérifiez votre connexion puis réessayez."
        onRetry={retry}
      />
    )
  if (!d) return <Skeleton caption="On fait les comptes…" />
  const max = Math.max(1, ...d.days.map((x) => x.amount))
  return (
    <div className="page-stack">
      <PageHead
        title="Bilan"
        sub="Vos ventes des trois derniers mois et ce que rapporte chaque arrivage."
      />
      <div className="page-pair">
        <Sheet aria-labelledby="bilan-ventes">
          <h2 className="section-title" id="bilan-ventes">
            Ventes par mois
          </h2>
          <p className="muted bilan__note">
            Trois derniers mois complets, ventes de test comprises.
          </p>
          <div
            className="bars"
            role="img"
            aria-label={d.days.map((x) => `${x.label} : ${money(x.amount)}`).join(', ')}
          >
            {d.days.map((x) => (
              <div className="bars__col" key={x.date}>
                <span className="bars__value">{x.amount ? fcfa(x.amount) : '0'}</span>
                <span
                  className="bars__bar"
                  style={{ height: `${Math.max(2, (x.amount / max) * 100)}%` }}
                />
              </div>
            ))}
          </div>
          <div className="bars__labels" aria-hidden="true">
            {d.days.map((x) => (
              <span key={x.date}>{x.label}</span>
            ))}
          </div>
        </Sheet>
        <Sheet aria-labelledby="bilan-categories">
          <h2 className="section-title" id="bilan-categories">
            Catégories vendues
          </h2>
          {d.categories.length === 0 ? (
            <p className="muted">Les catégories apparaîtront après vos premières ventes.</p>
          ) : (
            <Ledger label="Catégories vendues">
              {d.categories.map(([category, count]) => (
                <LedgerRow key={category} label={category} value={plural(count, 'vendu')} />
              ))}
            </Ledger>
          )}
        </Sheet>
      </div>
      <Sheet aria-labelledby="bilan-arrivages">
        <h2 className="section-title" id="bilan-arrivages">
          Rentabilité des arrivages
        </h2>
        {d.profit.length === 0 ? (
          <p className="muted">Aucun arrivage à analyser.</p>
        ) : (
          d.profit.map((x) => <ArrivalProfitRow key={x.id} arrival={x} />)
        )}
      </Sheet>
    </div>
  )
}
