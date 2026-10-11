import { useCallback, useMemo, useState } from 'react'
import { CloudOffIcon, InfoIcon, PlusIcon } from '../../components/icons'
import { Button, ButtonLink, Notice, Skeleton } from '../../components/ui'
import { useAsyncData } from '../../hooks/useAsyncData'
import { listSales } from '../../lib/covi'
import '../../styles/app/ventes.css'
import { DeviceSales } from './DeviceSales'
import { journalLines, SALES_LIMIT } from './journal'
import { NoSaleYet, SalesJournal } from './SalesJournal'

/**
 * Ventes: what the device still holds (refused or waiting sales), then the notebook of sales,
 * grouped by day, most recent first.
 */
export function HistoryPage({ shopId }: { shopId: string }) {
  const load = useCallback(() => listSales(shopId), [shopId])
  const { data: sales, error, retry } = useAsyncData(load)
  const lines = useMemo(() => (sales ? journalLines(sales) : null), [sales])
  // « Aujourd’hui » is fixed when the page opens, so the filters do not move under the finger.
  const [now] = useState(() => new Date())

  return (
    <div className="sales-page">
      <header className="page-head">
        <div>
          <h1>Ventes</h1>
          <p className="page-head__sub">Les plus récentes en haut.</p>
        </div>
        <ButtonLink write variant="sale" href="#/vendre" icon={<PlusIcon />}>
          Nouvelle vente
        </ButtonLink>
      </header>

      <DeviceSales shopId={shopId} />

      {error ? (
        <Notice
          icon={CloudOffIcon}
          title="Les ventes ne s’affichent pas : pas de réseau."
          actions={
            <Button variant="secondary" onClick={retry}>
              Réessayer
            </Button>
          }
        >
          <p>Réessayez dans un instant. Les ventes faites sans réseau restent gardées.</p>
        </Notice>
      ) : !lines || !sales ? (
        <Skeleton caption="On ouvre le cahier des ventes…" />
      ) : (
        <SalesJournal
          lines={lines}
          now={now}
          empty={
            <NoSaleYet
              actions={
                <ButtonLink write variant="sale" href="#/vendre">
                  Nouvelle vente
                </ButtonLink>
              }
            />
          }
          footer={
            sales.length >= SALES_LIMIT && (
              <Notice className="journal__limit" icon={InfoIcon} live={false}>
                <p>
                  Seules les {SALES_LIMIT} ventes les plus récentes s’affichent ici. Les plus
                  anciennes restent gardées sur votre compte.
                </p>
              </Notice>
            )
          }
        />
      )}
    </div>
  )
}
