import { money, plural } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'
import type { Arrival } from '../../lib/types'

/** Recovery progress and registered products of an arrival. */
export function ArrivalDetail({
  arrival: a,
  detail,
}: {
  arrival: Arrival
  detail: ArrivalProfit | undefined
}) {
  return (
    <div className="arrival-detail">
      <div className="progress">
        <i style={{ width: Math.min(100, detail?.recovery || 0) + '%' }} />
      </div>
      <div className="arrival-detail-kpis">
        <span>
          Produits enregistrés<b>{detail?.productCount ?? 0}</b>
        </span>
        <span>
          Produits vendus<b>{detail?.sold ?? 0}</b>
        </span>
        <span>
          Restants<b>{detail?.remaining ?? 0}</b>
        </span>
        <span>
          Ventes générées<b>{money(detail?.revenue ?? 0)}</b>
        </span>
        <span>
          Récupération<b>{detail?.recovery ?? 0}%</b>
        </span>
        <span>
          Reste à récupérer<b>{money(detail?.outstanding ?? Number(a.global_cost))}</b>
        </span>
      </div>
      <p className="arrival-item__meta">La récupération du coût n’est pas un bénéfice net après toutes les charges.</p>
      {detail?.products?.length ? (
        <div className="arrival-product-list">
          {detail.products.map((product) => (
            <div key={product.id}>
              <b>{product.name}</b>
              <span>
                {[product.category, product.brand, product.size].filter(Boolean).join(' · ') ||
                  'Référence'}{' '}
                · {plural(product.quantity_on_hand, 'restant')} · prix initial{' '}
                {money(Number(product.initial_sale_price))}
              </span>
            </div>
          ))}
        </div>
      ) : (
        <p>
          Les produits apparaîtront ici lorsque vous les enregistrerez à la réception. Pour un
          ballon, COVI les ajoute au fur et à mesure de son ouverture.
        </p>
      )}
    </div>
  )
}
