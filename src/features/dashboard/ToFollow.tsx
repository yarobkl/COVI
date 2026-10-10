import { Badge, cx, Ruler } from '../../components/ui'
import { shortDay } from '../../lib/dates'
import { fcfa, money, percent, plural } from '../../lib/format'
import type { ArrivalProfit, Dashboard } from '../../lib/operations'

const statusLabel: Record<string, string> = {
  draft: 'Pas encore commandé',
  ordered: 'Commandé',
  in_transit: 'En route',
}

/** « À suivre »: the bale being sold, low stock, arrivals not received yet. */
export function ToFollow({
  balloons,
  lowStock,
  arrivals,
  stock,
  className,
}: {
  balloons: ArrivalProfit[]
  lowStock: Dashboard['lowStock']
  arrivals: Dashboard['arrivalsInProgress']
  stock: number
  className?: string
}) {
  const nothing = !balloons.length && !lowStock.length && !arrivals.length
  return (
    <section className={cx('follow', className)} aria-labelledby="home-follow">
      <h2 className="section-title" id="home-follow">
        À suivre
      </h2>
      {nothing ? (
        <p className="follow__calm">Rien qui presse : pas d’arrivage attendu, pas de stock bas.</p>
      ) : (
        <ul className="follow__list">
          {balloons.slice(0, 2).map((b) => {
            const pieces = b.sold + b.remaining
            return (
              <li className="follow__item" key={b.id}>
                <p className="follow__title">Ballon {b.code}</p>
                <p>
                  {pieces > 0 &&
                    `${b.sold} ${b.sold > 1 ? 'pièces vendues' : 'pièce vendue'} sur ${pieces}. `}
                  <span className="figures">{fcfa(b.revenue)}</span>&nbsp;FCFA récupérés sur les{' '}
                  <span className="figures">{fcfa(b.cost)}</span> payés.
                </p>
                <Ruler
                  value={b.recovery}
                  label={`${money(b.revenue)} récupérés sur ${money(b.cost)}, soit ${percent(b.recovery)}`}
                />
                <p>
                  Encore <strong className="figures">{fcfa(b.cost - b.revenue)}</strong>&nbsp;FCFA à
                  récupérer.{' '}
                  <a href="#/arrivages/ballons">
                    Voir {b.remaining > 1 ? `les ${b.remaining} pièces qui restent` : 'le ballon'}
                  </a>
                </p>
              </li>
            )
          })}
          {lowStock.length > 0 && (
            <li className="follow__item">
              <p className="follow__title">Bientôt épuisé</p>
              {lowStock.slice(0, 3).map((p) => (
                <p key={p.id}>
                  {p.name} : <mark>plus que {p.quantity_on_hand}</mark>
                </p>
              ))}
              <p>
                {lowStock.length > 3 && `${plural(lowStock.length - 3, 'autre modèle')} · `}
                <a href="#/stock">Voir le stock</a>
              </p>
            </li>
          )}
          {arrivals.map((a) => (
            <li className="follow__item" key={a.id}>
              <p className="follow__title">
                {a.kind === 'balloon' ? 'Ballon' : 'Commande'} {a.code}
                {a.origin_country && <span className="muted"> — {a.origin_country}</span>}{' '}
                <Badge tone={a.status === 'in_transit' ? 'transit' : undefined}>
                  {statusLabel[a.status] ?? a.status}
                </Badge>
              </p>
              <p className="muted">
                {a.order_date && a.status !== 'draft'
                  ? `Commandé le ${shortDay(new Date(a.order_date))} · `
                  : ''}
                <a href="#/arrivages">Suivre l’arrivage</a>
              </p>
            </li>
          ))}
        </ul>
      )}
      <p className="follow__stock">
        {plural(stock, 'pièce')} en boutique · <a href="#/stock">Stock</a>
      </p>
    </section>
  )
}
