import { useCallback, useMemo } from 'react'
import { LoadError } from '../../components/LoadError'
import { useAsyncData } from '../../hooks/useAsyncData'
import { listSales } from '../../lib/covi'
import type { SoldItem } from '../../lib/types'
import { SoldRow } from './SoldRow'

/** Every sold line, most recent sale first. */
export function HistoryPage({ shopId }: { shopId: string }) {
  const load = useCallback(() => listSales(shopId), [shopId])
  const { data: rows, error, retry } = useAsyncData(load)
  const items = useMemo<SoldItem[] | null>(
    () =>
      rows &&
      rows.flatMap((s) =>
        (s.sale_items ?? []).map((i) => ({
          ...i,
          sold_at: s.sold_at,
          payment_method: s.payment_method,
          id: s.id,
          is_test: s.is_test,
        })),
      ),
    [rows],
  )
  return (
    <>
      <div className="hello">
        <div>
          <h1>Produits vendus</h1>
          <span>Historique des ventes · les lignes TEST sont fictives.</span>
        </div>
      </div>
      {error ? (
        <LoadError
          message="Impossible de charger l’historique des ventes. Vérifiez votre connexion puis réessayez."
          onRetry={retry}
        />
      ) : (
        <section className="card">
          {items === null ? (
            <p>Chargement des ventes…</p>
          ) : items.length === 0 ? (
            <p>Aucune vente enregistrée.</p>
          ) : (
            items.map((x, i) => <SoldRow key={x.id + i} item={x} />)
          )}
        </section>
      )}
    </>
  )
}
