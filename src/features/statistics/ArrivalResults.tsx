import { Badge, Ruler, Stamp } from '../../components/ui'
import { fcfa, money, percent, plural } from '../../lib/format'
import '../../styles/app/bilan.css'
import type { ArrivalResult } from './bilanMath'

const sold = (n: number) => `${n} ${n > 1 ? 'vendues' : 'vendue'}`
const left = (n: number) => (n > 1 ? `${n} restent` : `${n} reste`)

/**
 * « Ce que chaque arrivage a rapporté »: what it cost, what its pieces brought in, a graduated
 * ruler, then « Encore 64 000 FCFA à récupérer » or « A rapporté 340 000 FCFA » with the
 * RENTABILISÉ stamp.
 */
export function ArrivalResults({ arrivals }: { arrivals: ArrivalResult[] }) {
  return (
    <ul className="arrival-results">
      {arrivals.map((a) => {
        const done = a.cost > 0 && a.revenue >= a.cost
        const pieces = a.sold + a.remaining
        return (
          <li
            className={done ? 'arrival-result arrival-result--done' : 'arrival-result'}
            key={a.id}
          >
            <p className="arrival-result__title">
              {a.kind === 'balloon' ? 'Ballon' : 'Commande'}{' '}
              <span className="figures">{a.code}</span>
              {a.origin && <span className="arrival-result__origin"> — {a.origin}</span>}
              {a.example && <Badge>Exemple</Badge>}
            </p>
            <p className="arrival-result__figures">
              Payé <strong className="figures">{fcfa(a.cost)}</strong> · ventes{' '}
              <strong className="figures">{fcfa(a.revenue)}</strong>&nbsp;FCFA
              {pieces > 0 && (
                <span className="arrival-result__pieces">
                  {' '}
                  · {plural(pieces, 'pièce')} : {sold(a.sold)}, {left(a.remaining)}
                </span>
              )}
            </p>
            {a.cost > 0 && (
              <Ruler
                value={a.recovery}
                label={`${money(a.revenue)} récupérés sur ${money(a.cost)}, soit ${percent(a.recovery)}`}
              />
            )}
            <p className="arrival-result__verdict">
              {a.cost <= 0 ? (
                'Prix payé pas noté : impossible de dire ce qu’il a rapporté.'
              ) : done ? (
                <>
                  <span className="visually-hidden">Rentabilisé. </span>
                  <strong className="arrival-result__gain">
                    A rapporté <span className="figures">{fcfa(a.revenue - a.cost)}</span>
                    &nbsp;FCFA
                  </strong>{' '}
                  une fois payé.
                </>
              ) : (
                <>
                  Encore <strong className="figures">{fcfa(a.cost - a.revenue)}</strong>&nbsp;FCFA à
                  récupérer.
                </>
              )}
            </p>
            {done && (
              <span className="arrival-result__stamp">
                <Stamp kind="done" size="sm">
                  Rentabilisé
                </Stamp>
              </span>
            )}
          </li>
        )
      })}
    </ul>
  )
}
