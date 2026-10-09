import { useEffect, useMemo, useState } from 'react'
import { listSales, type SoldItem } from '../../lib/covi'
import { SoldRow } from './SoldRow'

type Sales = Awaited<ReturnType<typeof listSales>>

/** Every sold line, most recent sale first. */
export function HistoryPage({ shopId }: { shopId: string }) {
  const [rows, setRows] = useState<Sales>([])
  useEffect(() => {
    listSales(shopId).then(setRows)
  }, [shopId])
  const items = useMemo<SoldItem[]>(
    () =>
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
      <section className="card">
        {items.length === 0 ? (
          <p>Aucune vente enregistrée.</p>
        ) : (
          items.map((x, i) => <SoldRow key={x.id + i} item={x} />)
        )}
      </section>
    </>
  )
}
