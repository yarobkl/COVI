import type { CSSProperties } from 'react'
import { fcfa, money } from '../../lib/format'
import '../../styles/app/bilan.css'

/**
 * Sales per month as plain ink bars on a ruled baseline, each one labelled with its amount
 * (cash-register figures) and its month. No gradient, no colour code: the table under it gives
 * the same figures.
 */
export function MonthBars({
  months,
}: {
  months: { key: string; label: string; amount: number }[]
}) {
  const max = Math.max(1, ...months.map((m) => m.amount))
  const summary = months.map((m) => `${m.label} ${money(m.amount)}`).join(', ')
  return (
    <figure className="month-bars" role="img" aria-label={`Ventes par mois : ${summary}`}>
      <div className="month-bars__plot" aria-hidden="true">
        {months.map((m) => (
          <div className="month-bars__col" key={m.key}>
            <span className="month-bars__value figures">{fcfa(m.amount)}</span>
            <span
              className={m.amount > 0 ? 'month-bars__bar' : 'month-bars__bar month-bars__bar--zero'}
              style={{ '--ratio': m.amount / max } as CSSProperties}
            />
          </div>
        ))}
      </div>
      <div className="month-bars__axis" aria-hidden="true">
        {months.map((m) => (
          <span key={m.key}>{m.label}</span>
        ))}
      </div>
    </figure>
  )
}
