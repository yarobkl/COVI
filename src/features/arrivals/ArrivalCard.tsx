import { money } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'
import type { Arrival } from '../../lib/types'
import { ArrivalDetail } from './ArrivalDetail'
import { nextStatusLabel, statusLabel } from './arrivalStatus'

/** One arrival: status, lifecycle action, key figures and optional detail. */
export function ArrivalCard({
  arrival: a,
  profit: p,
  busy,
  expanded,
  onAdvance,
  onAddProduct,
  onToggleDetail,
}: {
  arrival: Arrival
  profit: ArrivalProfit | undefined
  busy: boolean
  expanded: boolean
  onAdvance: () => void
  onAddProduct: () => void
  onToggleDetail: () => void
}) {
  return (
    <div className="ordercard">
      <div>
        <span className={'pill ' + (a.status === 'received' ? 'green' : 'amber')}>
          {a.kind === 'balloon' ? 'BALLON' : 'FOURNISSEUR'} · {statusLabel(a.status)}
        </span>
        <h3>
          {a.code} {a.is_test && <em className="test-tag">TEST</em>}
          {a.supplier_name ? ' · ' + a.supplier_name : ''}
        </h3>
        <p>
          {a.origin_country || 'Origine non renseignée'} ·{' '}
          {a.order_date ? 'Commandé le ' + a.order_date : 'Date de commande à confirmer'}
          {a.received_date ? ' · Reçu le ' + a.received_date : ''}
        </p>
        {a.status !== 'received' && (
          <button className="outline" disabled={busy} onClick={onAdvance}>
            {nextStatusLabel[a.status]}
          </button>
        )}
      </div>
      <div className="orderstats">
        <button
          className="outline"
          disabled={a.status !== 'received'}
          title={
            a.status !== 'received'
              ? 'Marquez l’arrivage comme reçu avant d’ajouter les produits'
              : ''
          }
          onClick={onAddProduct}
        >
          Ajouter produit
        </button>
        <button className="outline" onClick={onToggleDetail}>
          {expanded ? 'Fermer le détail' : 'Voir le détail'}
        </button>
        <span>
          Coût total<b>{money(Number(a.global_cost))}</b>
        </span>
        {p ? (
          <>
            <span>
              Vendus / restants
              <b>
                {p.sold} / {p.remaining}
              </b>
            </span>
            <span>
              Récupéré<b>{p.recovery}%</b>
            </span>
            <span>
              Résultat actuel
              <b>
                {p.profit >= 0 ? '+ ' : ''}
                {money(p.profit)}
              </b>
            </span>
          </>
        ) : null}
      </div>
      {expanded && <ArrivalDetail arrival={a} detail={p} />}
    </div>
  )
}
