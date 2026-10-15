import { Badge, Button, Ledger, LedgerRow, Ruler } from '../../components/ui'
import { isoDayLabel } from '../../lib/dates'
import { fcfa, money } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'
import type { Arrival } from '../../lib/types'
import { ArrivalDetail } from './ArrivalDetail'
import { nextStatusLabel } from './arrivalStatus'

const statusText: Record<string, string> = {
  received: 'reçu',
  in_transit: 'en route',
  ordered: 'commandé',
  draft: 'brouillon',
}
const statusTone = (status: string) =>
  status === 'received' ? 'success' : status === 'in_transit' ? 'transit' : 'waiting'

/** One arrival written as an entry of the notebook: what, where from, the figures, what to do. */
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
  const cost = Number(a.global_cost)
  return (
    <article className="entry" aria-labelledby={`arrival-${a.id}`}>
      <div className="entry__head">
        <h3 className="entry__title" id={`arrival-${a.id}`}>
          {a.code}
          {a.supplier_name ? ' · ' + a.supplier_name : ''}
          {a.is_test && <span className="test-note">test</span>}
        </h3>
        <Badge tone={statusTone(a.status)}>
          {a.kind === 'balloon' ? 'Ballon' : 'Fournisseur'} · {statusText[a.status] ?? a.status}
        </Badge>
      </div>
      <p className="entry__meta">
        {a.origin_country || 'Origine non renseignée'} ·{' '}
        {a.order_date ? 'commandé le ' + isoDayLabel(a.order_date) : 'date de commande à confirmer'}
        {a.received_date ? ' · reçu le ' + isoDayLabel(a.received_date) : ''}
      </p>
      <Ledger label={`Chiffres de ${a.code}`}>
        <LedgerRow label="Coût total" value={<span className="figures">{money(cost)}</span>} />
        {p && (
          <>
            <LedgerRow
              label="Vendus / restants"
              value={
                <span className="figures">
                  {p.sold} / {p.remaining}
                </span>
              }
            />
            <LedgerRow
              variant="total"
              label="Résultat actuel"
              value={
                <span className={'figures' + (p.profit < 0 ? ' amount-out' : '')}>
                  {p.profit >= 0 ? '+ ' : ''}
                  {money(p.profit)}
                </span>
              }
            />
          </>
        )}
      </Ledger>
      {p && cost > 0 && (
        <Ruler
          value={p.recovery}
          label={`${fcfa(p.revenue)} FCFA récupérés sur ${fcfa(cost)}, soit ${p.recovery} %`}
        />
      )}
      <div className="row-actions">
        {a.status !== 'received' && (
          <Button variant="primary" disabled={busy} onClick={onAdvance}>
            {nextStatusLabel[a.status]}
          </Button>
        )}
        <Button
          variant="secondary"
          disabled={a.status !== 'received'}
          title={
            a.status !== 'received'
              ? 'Marquez l’arrivage comme reçu avant d’ajouter les produits'
              : undefined
          }
          onClick={onAddProduct}
        >
          {a.status === 'received' ? 'Ajouter un produit' : 'Produits après réception'}
        </Button>
        <Button variant="ghost" aria-expanded={expanded} onClick={onToggleDetail}>
          {expanded ? 'Fermer le détail' : 'Voir le détail'}
        </Button>
      </div>
      {expanded && <ArrivalDetail arrival={a} detail={p} />}
    </article>
  )
}
