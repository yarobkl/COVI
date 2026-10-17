import { Badge, Ledger, LedgerRow, Ruler } from '../../components/ui'
import { fcfa, money } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'

/** What one arrival cost, what it has brought back and where it stands, as a notebook entry. */
export function ArrivalProfitRow({ arrival: x }: { arrival: ArrivalProfit }) {
  return (
    <article className="entry" aria-labelledby={`profit-${x.id}`}>
      <div className="entry__head">
        <h3 className="entry__title" id={`profit-${x.id}`}>
          {x.code}
          {x.is_test && <span className="test-note">test</span>}
        </h3>
        <Badge tone={x.recovery >= 100 ? 'success' : 'waiting'}>
          {x.recovery >= 100 ? 'Rentabilisé' : `${x.recovery} % récupéré`}
        </Badge>
      </div>
      <p className="entry__meta">
        {x.kind === 'balloon' ? 'Ballon / lot mixte' : x.supplier || 'Commande fournisseur'} ·{' '}
        {x.origin || 'Origine non renseignée'}
      </p>
      <Ledger label={`Rentabilité de ${x.code}`}>
        <LedgerRow label="Investi" value={<span className="figures">{money(x.cost)}</span>} />
        <LedgerRow
          label="Ventes générées"
          value={<span className="figures">{money(x.revenue)}</span>}
        />
        <LedgerRow
          variant="total"
          label="Ventes moins coût total de l’arrivage"
          value={
            <span className={'figures' + (x.profit < 0 ? ' amount-out' : '')}>
              {x.profit >= 0 ? '+ ' : ''}
              {money(x.profit)}
            </span>
          }
        />
      </Ledger>
      <p className="muted">
        Ce solde mesure la récupération de l’investissement de cet arrivage, pas le bénéfice net de
        l’entreprise.
      </p>
      {x.cost > 0 && (
        <Ruler
          value={x.recovery}
          label={`${fcfa(x.revenue)} FCFA récupérés sur ${fcfa(x.cost)}, soit ${x.recovery} %`}
        />
      )}
    </article>
  )
}
