import type { ComponentPropsWithRef, ReactNode } from 'react'
import { cx } from './cx'

export type IconButtonProps = Omit<ComponentPropsWithRef<'button'>, 'aria-label' | 'children'> & {
  /** Accessible name saying what the button acts on (« Supprimer Loyer », not « Supprimer »). */
  label: string
  variant?: 'plain' | 'outlined' | 'danger' | 'tactile'
  children: ReactNode
}

/** Button showing only an icon: 44 px target (48 px for the tactile sale variant). */
export function IconButton({
  label,
  variant = 'plain',
  className,
  children,
  type = 'button',
  ...rest
}: IconButtonProps) {
  return (
    <button
      {...rest}
      type={type}
      aria-label={label}
      className={cx('icon-btn', variant !== 'plain' && `icon-btn--${variant}`, className)}
    >
      {children}
    </button>
  )
}
