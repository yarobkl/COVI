import { money } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'

/** Investment, revenue and current result of one arrival. */
export function ArrivalProfitRow({ arrival: x }: { arrival: ArrivalProfit }) {
  return (
    <div className="ordercard">
      <div>
        <span className={'pill ' + (x.recovery >= 100 ? 'green' : 'amber')}>
          {x.recovery >= 100 ? 'RENTABILISÉ' : x.recovery + '% RÉCUPÉRÉ'}
        </span>
        <h3>
          {x.code} {x.is_test && <em className="test-tag">TEST</em>}
        </h3>
        <p>
          {x.kind === 'balloon' ? 'Ballon / lot mixte' : x.supplier || 'Commande fournisseur'} ·{' '}
          {x.origin || 'Origine non renseignée'}
        </p>
      </div>
      <div className="orderstats">
        <span>
          Investi<b>{money(x.cost)}</b>
        </span>
        <span>
          Ventes générées<b>{money(x.revenue)}</b>
        </span>
        <span>
          Résultat actuel
          <b>
            {x.profit >= 0 ? '+ ' : ''}
            {money(x.profit)}
          </b>
        </span>
      </div>
    </div>
  )
}
