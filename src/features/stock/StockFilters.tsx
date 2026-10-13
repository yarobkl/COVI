import { useId } from 'react'
import type { Arrival } from '../../lib/types'
import type { StockFilter } from './stockFilters'

const choices: readonly { value: StockFilter; label: string }[] = [
  { value: 'all', label: 'Tout' },
  { value: 'low', label: 'Bientôt épuisé' },
  { value: 'unique', label: 'Pièces uniques' },
]

/**
 * « Tout · Bientôt épuisé · Pièces uniques » (real radio buttons drawn as tabs) and the arrival the
 * articles came from.
 */
export function StockFilters({
  filter,
  onFilter,
  counts,
  arrival,
  onArrival,
  arrivals,
  hasLoose,
}: {
  filter: StockFilter
  onFilter: (filter: StockFilter) => void
  counts: Record<StockFilter, number>
  arrival: string
  onArrival: (arrival: string) => void
  arrivals: readonly Pick<Arrival, 'id' | 'code' | 'kind'>[]
  /** Some articles have no arrival: « Sans arrivage » is offered. */
  hasLoose: boolean
}) {
  const name = useId()
  const selectId = useId()
  return (
    <div className="stock-filters">
      <fieldset className="stock-chips">
        <legend className="visually-hidden">Afficher</legend>
        {choices.map((c) => (
          <label key={c.value} className="stock-chip">
            <input
              className="stock-chip__input"
              type="radio"
              name={name}
              value={c.value}
              checked={filter === c.value}
              onChange={() => onFilter(c.value)}
            />
            <span className="stock-chip__label">
              {c.label} <span className="stock-chip__count">{counts[c.value]}</span>
            </span>
          </label>
        ))}
      </fieldset>
      {arrivals.length > 0 && (
        <div className="stock-arrival">
          <label className="stock-arrival__label" htmlFor={selectId}>
            Arrivage
          </label>
          <select
            id={selectId}
            className="select stock-arrival__select"
            value={arrival}
            onChange={(e) => onArrival(e.target.value)}
          >
            <option value="">Tous</option>
            {arrivals.map((a) => (
              <option key={a.id} value={a.id}>
                {a.code} · {a.kind === 'balloon' ? 'ballon' : 'commande'}
              </option>
            ))}
            {hasLoose && <option value="none">Sans arrivage</option>}
          </select>
        </div>
      )}
    </div>
  )
}
