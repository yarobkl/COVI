import type { ComponentPropsWithRef, MouseEvent, ReactNode } from 'react'
import { cx } from './cx'
import { useWriteLock } from './writeLock'

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'sale' | 'tactile'
export type ButtonSize = 'md' | 'lg' | 'xl'

type Look = {
  /** `sale` (inked key with a solid shadow) is reserved for the sale and its entry points. */
  variant?: ButtonVariant
  /** 44 px (md), 56 px (lg) or 64 px (xl). */
  size?: ButtonSize
  block?: boolean
  /** Filled red, for the confirmation of a destructive action only (with `variant="danger"`). */
  solid?: boolean
  /** Icon shown before the label (decorative). */
  icon?: ReactNode
  /** Writes in the shop (sell, add…): disabled with its reason while the shop is read only. */
  write?: boolean
}

const lookClass = ({ variant = 'secondary', size = 'md', block, solid }: Look, extra?: string) =>
  cx(
    'btn',
    `btn--${variant}`,
    size !== 'md' && `btn--${size}`,
    block && 'btn--block',
    solid && 'btn--solid',
    extra,
  )

export type ButtonProps = ComponentPropsWithRef<'button'> &
  Look & {
    /** Waiting for the server: the label becomes `busyLabel` and clicks are ignored. */
    busy?: boolean
    busyLabel?: string
  }

/**
 * Design-system button. A disabled button should say why in its label
 * (« Choisissez comment la cliente paie »), never stay silently grey.
 */
export function Button({
  variant,
  size,
  block,
  solid,
  icon,
  busy = false,
  busyLabel = 'Un instant…',
  className,
  children,
  type = 'button',
  onClick,
  write,
  ...rest
}: ButtonProps) {
  const lock = useWriteLock()
  const locked = write && lock
  return (
    <button
      {...rest}
      {...(locked && {
        disabled: true,
        title: lock.reason,
        'aria-describedby': lock.reasonId,
      })}
      type={type}
      className={lookClass({ variant, size, block, solid }, className)}
      aria-busy={busy || undefined}
      onClick={(e: MouseEvent<HTMLButtonElement>) => {
        if (busy) {
          e.preventDefault()
          return
        }
        onClick?.(e)
      }}
    >
      {icon}
      {busy ? busyLabel : children}
    </button>
  )
}

export type ButtonLinkProps = ComponentPropsWithRef<'a'> & Look & { href: string }

/** A link that looks like a button (navigation such as « Nouvelle vente »). */
export function ButtonLink({
  variant,
  size,
  block,
  solid,
  icon,
  className,
  children,
  write,
  ...rest
}: ButtonLinkProps) {
  const lock = useWriteLock()
  if (write && lock) {
    // Read only: same place and look, disabled, never a way into a write screen.
    // eslint-disable-next-line @typescript-eslint/no-unused-vars -- the link is dropped
    const { href, onClick, ...kept } = rest
    return (
      <a
        {...kept}
        role="link"
        aria-disabled="true"
        aria-describedby={lock.reasonId}
        title={lock.reason}
        className={lookClass({ variant, size, block, solid }, className)}
      >
        {icon}
        {children}
      </a>
    )
  }
  return (
    <a {...rest} className={lookClass({ variant, size, block, solid }, className)}>
      {icon}
      {children}
    </a>
  )
}
