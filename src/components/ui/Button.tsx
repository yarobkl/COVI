import type { ComponentPropsWithRef, MouseEvent, ReactNode } from 'react'
import { cx } from './cx'

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
  ...rest
}: ButtonProps) {
  return (
    <button
      {...rest}
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
  ...rest
}: ButtonLinkProps) {
  return (
    <a {...rest} className={lookClass({ variant, size, block, solid }, className)}>
      {icon}
      {children}
    </a>
  )
}
