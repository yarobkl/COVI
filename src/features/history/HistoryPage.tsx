import { useCallback, useMemo } from 'react'
import { LoadError } from '../../components/LoadError'
import { useAsyncData } from '../../hooks/useAsyncData'
import { listSales } from '../../lib/covi'
import { listCategorySaleHistory } from '../../lib/categorySaleHistory'
import type { SoldItem } from '../../lib/types'
import { SoldRow } from './SoldRow'
import { CategorySoldRow } from './CategorySoldRow'

/** Legacy product sales and category-only receipts, most recent first. */
export function HistoryPage({ shopId }: { shopId: string }) {
  const load = useCallback(async () => {
    const [legacy, categories] = await Promise.all([
      listSales(shopId),
      listCategorySaleHistory(shopId),
    ])
    return { legacy, categories }
  }, [shopId])
  const { data: rows, error, retry } = useAsyncData(load)
  const items = useMemo(() => {
    if (!rows) return null
    const legacy = rows.legacy.flatMap((s) =>
      (s.sale_items ?? []).map((i) => ({
        kind: 'product' as const,
        soldAt: s.sold_at,
        key: s.id + ':' + i.products?.name + ':' + i.quantity,
        item: {
          ...i,
          sold_at: s.sold_at,
          payment_method: s.payment_method,
          id: s.id,
          is_test: s.is_test,
        } satisfies SoldItem,
      })),
    )
    const category = rows.categories.flatMap((r) =>
      r.lines.map((line, index) => ({
        kind: 'category' as const,
        soldAt: r.confirmedAt,
        key: r.saleId + ':' + index,
        receipt: r,
        line,
      })),
    )
    return [...legacy, ...category].sort(
      (a, b) => new Date(b.soldAt).getTime() - new Date(a.soldAt).getTime(),
    )
  }, [rows])
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
            items.map((x) =>
              x.kind === 'product' ? (
                <SoldRow key={x.key} item={x.item} />
              ) : (
                <CategorySoldRow key={x.key} receipt={x.receipt} line={x.line} />
              ),
            )
          )}
        </section>
      )}
    </>
  )
}
