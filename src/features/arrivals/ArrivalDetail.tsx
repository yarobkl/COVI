import { Ledger, LedgerRow } from '../../components/ui'
import { money, plural } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'
import type { Arrival } from '../../lib/types'

/** What an arrival has become: products registered, sold, left, and the money back. */
export function ArrivalDetail({
  arrival: a,
  detail,
}: {
  arrival: Arrival
  detail: ArrivalProfit | undefined
}) {
  return (
    <div className="entry__detail">
      <Ledger label={`Détail de ${a.code}`}>
        <LedgerRow label="Produits enregistrés" value={detail?.productCount ?? 0} />
        <LedgerRow label="Produits vendus" value={detail?.sold ?? 0} />
        <LedgerRow label="Restants" value={detail?.remaining ?? 0} />
        <LedgerRow
          label="Ventes générées"
          value={<span className="figures">{money(detail?.revenue ?? 0)}</span>}
        />
        <LedgerRow label="Récupération" value={`${detail?.recovery ?? 0} %`} />
      </Ledger>
      {detail?.products?.length ? (
        <>
          <h4 className="entry__subtitle">Produits de l’arrivage</h4>
          <Ledger label={`Produits de ${a.code}`}>
            {detail.products.map((product) => (
              <LedgerRow
                key={product.id}
                label={product.name}
                meta={[
                  [product.category, product.brand, product.size].filter(Boolean).join(' · ') ||
                    'Référence',
                  plural(product.quantity_on_hand, 'restant'),
                ].join(' · ')}
                value={<span className="figures">{money(Number(product.initial_sale_price))}</span>}
              />
            ))}
          </Ledger>
        </>
      ) : (
        <p className="muted">
          Les produits apparaîtront ici lorsque vous les enregistrerez à la réception. Pour un
          ballon, COVI les ajoute au fur et à mesure de son ouverture.
        </p>
      )}
    </div>
  )
}
