import type { CSSProperties } from 'react'
import { fcfa, money, paymentLabel } from '../../lib/format'

/** How today's money came in, as one bar drawn in ink (plain, hatched, dotted…) and its legend. */
export function PaymentSplit({ parts }: { parts: { method: string; amount: number }[] }) {
  const total = parts.reduce((a, p) => a + p.amount, 0)
  if (total <= 0 || parts.length < 1) return null
  const label = parts.map((p) => `${paymentLabel(p.method)} ${money(p.amount)}`).join(', ')
  return (
    <div className="pay-split">
      <div className="pay-split__bar" role="img" aria-label={label}>
        {parts.map((p, i) => (
          <span
            key={p.method}
            className={`pay-split__part pay-split__part--${i % 4}`}
            style={{ '--share': `${(p.amount / total) * 100}%` } as CSSProperties}
          />
        ))}
      </div>
      <ul className="pay-split__legend" aria-hidden="true">
        {parts.map((p, i) => (
          <li key={p.method}>
            <span className={`pay-split__swatch pay-split__part--${i % 4}`} />
            {paymentLabel(p.method)} <span className="figures">{fcfa(p.amount)}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}
