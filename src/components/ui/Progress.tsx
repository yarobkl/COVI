import type { CSSProperties } from 'react'
import { percent } from '../../lib/format'
import { cx } from './cx'

/**
 * Graduated ruler showing how much of an arrival has come back (0 → 100 %, green once paid back).
 * Always pair it with the sentence in amounts (« 186 000 FCFA récupérés sur 250 000 »); `label`
 * repeats it for screen readers.
 */
export function Ruler({ value, label }: { value: number; label: string }) {
  const clamped = Math.max(0, Math.min(100, value))
  return (
    <div
      className={cx('ruler', value >= 100 && 'ruler--done')}
      role="img"
      aria-label={label}
      style={{ '--value': `${clamped}%` } as CSSProperties}
    >
      <span className="ruler__track" />
      <span className="ruler__fill" />
      <span className="ruler__mark" aria-hidden="true">
        {percent(value)}
      </span>
    </div>
  )
}
