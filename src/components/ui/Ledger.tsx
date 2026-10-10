import type { ReactNode } from 'react'
import { cx } from './cx'

/** A list written like the lines of the shop's notebook: label · dots · amount. */
export function Ledger({
  children,
  className,
  label,
}: {
  children: ReactNode
  className?: string
  /** Accessible name of the list when no visible heading names it. */
  label?: string
}) {
  return (
    <ul className={cx('ledger', className)} aria-label={label}>
      {children}
    </ul>
  )
}

/**
 * One notebook line. `head`: bold first line · `sub`: indented detail · `total`: rule above,
 * double rule below · `link`: the whole line is a touch target (put a single link in `label`).
 */
export function LedgerRow({
  label,
  meta,
  value,
  variant,
  className,
}: {
  label: ReactNode
  meta?: ReactNode
  value?: ReactNode
  variant?: 'head' | 'sub' | 'total' | 'link'
  className?: string
}) {
  return (
    <li className={cx('ledger__row', variant && `ledger__row--${variant}`, className)}>
      <span className="ledger__label">
        {label}
        {meta && <span className="ledger__meta">{meta}</span>}
      </span>
      <span className="ledger__dots" aria-hidden="true" />
      {value !== undefined && <span className="ledger__value">{value}</span>}
    </li>
  )
}
