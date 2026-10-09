import type { ComponentType, ReactNode } from 'react'
import { CheckIcon, CloudUpIcon, InfoIcon, type IconProps } from '../icons'
import { cx } from './cx'

/**
 * Message within the page. `calm` (blue-grey) for the network and things that will sort
 * themselves out, never red; `success` (green); `danger` (red) only when something needs doing.
 */
export function Notice({
  tone = 'calm',
  title,
  icon,
  actions,
  live = true,
  className,
  children,
}: {
  tone?: 'calm' | 'success' | 'danger'
  title?: ReactNode
  icon?: ComponentType<IconProps>
  actions?: ReactNode
  /** Announced when it appears (status, or alert for `danger`). */
  live?: boolean
  className?: string
  children?: ReactNode
}) {
  const IconComponent =
    icon ?? (tone === 'success' ? CheckIcon : tone === 'danger' ? InfoIcon : CloudUpIcon)
  return (
    <div
      className={cx('notice', tone !== 'calm' && `notice--${tone}`, className)}
      role={live ? (tone === 'danger' ? 'alert' : 'status') : undefined}
    >
      <IconComponent className="notice__icon" />
      <div className="notice__body">
        {title && <p className="notice__title">{title}</p>}
        {children}
        {actions && <div className="notice__actions">{actions}</div>}
      </div>
    </div>
  )
}
