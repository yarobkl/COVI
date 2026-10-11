import { money } from '../../lib/format'
import type { ArrivalProfit } from '../../lib/operations'
import type { Arrival } from '../../lib/types'
import { ArrivalDetail } from './ArrivalDetail'
import { nextStatusLabel, statusLabel } from './arrivalStatus'
import './arrivalActions.css'

/** One arrival, one obvious next action. Detail and finance remain accessible on demand. */
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
  const received = a.status === 'received'
  const kind = a.kind === 'balloon' ? 'Ballon' : 'Commande fournisseur'
  const action = received ? 'Ajouter des articles au stock' : nextStatusLabel[a.status]
  return (
    <article className="arrival-item">
      <div className="arrival-item__top">
        <span className={'pill ' + (received ? 'green' : 'amber')}>
          {kind} · {statusLabel(a.status)}
        </span>
        {a.is_test && <em className="test-tag">TEST</em>}
      </div>
      <h3 className="arrival-item__title">{a.code}{a.supplier_name ? ' · ' + a.supplier_name : ''}</h3>
      <p className="arrival-item__meta">
        {a.origin_country || 'Origine non renseignée'}
        {a.order_date ? ' · Commandée le ' + a.order_date : ''}
        {a.received_date ? ' · Reçue le ' + a.received_date : ''}
      </p>
      <div className="arrival-item__amount">
        <span>{received ? 'Coût de l’arrivage' : 'Montant prévu'}</span>
        <strong>{money(Number(a.global_cost))}</strong>
      </div>
      <div className="arrival-item__actions">
        <button
          type="button"
          className="arrival-item__button"
          disabled={busy || (!received && !nextStatusLabel[a.status])}
          onClick={received ? onAddProduct : onAdvance}
          aria-label={action || 'Action indisponible'}
        >
          {busy ? 'Un instant…' : action || 'Action indisponible'}
        </button>
        <button
          type="button"
          className="arrival-item__button arrival-item__button--quiet"
          aria-expanded={expanded}
          onClick={onToggleDetail}
        >
          {expanded ? 'Masquer les détails ↑' : 'Voir les détails →'}
        </button>
      </div>
      {expanded && (
        <div className="arrival-item__detail">
          {received && p && (
            <p className="arrival-item__meta">
              {p.sold} vendu(s) · {p.remaining} restant(s) · {p.recovery}% du coût récupéré
            </p>
          )}
          <ArrivalDetail arrival={a} detail={p} />
        </div>
      )}
    </article>
  )
}
