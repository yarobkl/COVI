import { fcfa } from '../../lib/format'
import { cx } from './cx'

export type AmountProps = {
  /** Whole CFA francs. A negative value is written with the true minus sign (« − 90 000 »). */
  value: number
  /** sm 16 px · md 19 px (list) · lg 30 px (total) · xl 44 px (pad) · hero 44 → 84 px. */
  size?: 'sm' | 'md' | 'lg' | 'xl' | 'hero'
  /** `out`: money going out (red pen) · `in`: money coming in (green). */
  tone?: 'in' | 'out'
  /** Displayed price crossed out in red after a negotiation. */
  struck?: boolean
  regular?: boolean
  /** Shows the small « FCFA » after the figures. */
  unit?: boolean
  className?: string
}

/** An amount in cash-register figures (Courier Prime), never wrapped across lines. */
export function Amount({
  value,
  size = 'md',
  tone,
  struck = false,
  regular = false,
  unit = false,
  className,
}: AmountProps) {
  return (
    <span
      className={cx(
        'amount',
        `amount--${size}`,
        tone && `amount--${tone}`,
        struck && 'amount--struck',
        regular && 'amount--regular',
        className,
      )}
    >
      {fcfa(value)}
      {unit && <span className="amount__unit">FCFA</span>}
    </span>
  )
}
