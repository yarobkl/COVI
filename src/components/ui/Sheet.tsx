import type { ComponentPropsWithRef, ReactNode } from 'react'
import { cx } from './cx'

/** A sheet of paper laid on the page: one per area, never a grid of identical cards. */
export function Sheet({
  seyes = false,
  className,
  children,
  ...rest
}: ComponentPropsWithRef<'section'> & { seyes?: boolean }) {
  return (
    <section {...rest} className={cx('sheet', seyes && 'sheet--seyes margin-rule', className)}>
      {children}
    </section>
  )
}

/** The notebook's label (shop name), framed twice in blue ink. */
export function LabelCard({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={cx('label-card', className)}>{children}</div>
}

/** Till receipt: Courier figures and a torn bottom edge. */
export function Ticket({
  head,
  sub,
  tilt = false,
  className,
  children,
}: {
  head?: ReactNode
  sub?: ReactNode
  tilt?: boolean
  className?: string
  children: ReactNode
}) {
  return (
    <div className={cx('ticket', tilt && 'ticket--tilt', className)}>
      {head && <p className="ticket__head">{head}</p>}
      {sub && <p className="ticket__sub">{sub}</p>}
      {(head || sub) && <hr className="ticket__cut" />}
      {children}
    </div>
  )
}

/** A receipt line: what (left) and how much (right, bold). */
export function TicketLine({
  left,
  right,
  className,
}: {
  left: ReactNode
  right: ReactNode
  className?: string
}) {
  return (
    <div className={cx('ticket__line', className)}>
      <span>{left}</span>
      <span>{right}</span>
    </div>
  )
}
