import type { ReactNode } from 'react'
import { cx } from './cx'

/**
 * Rubber stamp (PAYÉ, REÇU…): an object for a moment, one per screen at most. Upper case comes
 * from CSS; the text stays in sentence case. Decorative by default: say the same thing in text.
 */
export function Stamp({
  kind,
  size,
  drop = false,
  decorative = true,
  children,
}: {
  kind: 'paid' | 'received' | 'transit' | 'done'
  size?: 'sm' | 'lg'
  /** Falls onto the paper (bounce), for the sale celebration. */
  drop?: boolean
  decorative?: boolean
  children: ReactNode
}) {
  return (
    <span
      className={cx('stamp', `stamp--${kind}`, size && `stamp--${size}`, drop && 'stamp--drop')}
      aria-hidden={decorative || undefined}
    >
      {children}
    </span>
  )
}

/** Small lower-case tag in a list (« Ballon », « En route », « Plus que 1 »). */
export function Badge({
  tone,
  icon,
  children,
}: {
  tone?: 'action' | 'transit' | 'success' | 'danger' | 'low' | 'waiting'
  icon?: ReactNode
  children: ReactNode
}) {
  return (
    <span className={cx('badge', tone && `badge--${tone}`)}>
      {icon}
      {children}
    </span>
  )
}
