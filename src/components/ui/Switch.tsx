import type { ReactNode } from 'react'
import '../../styles/app/filters.css'
import { cx } from './cx'

/** On / off choice (a real checkbox announced as a switch), with its label beside it. */
export function Switch({
  checked,
  onChange,
  children,
  className,
}: {
  checked: boolean
  onChange: (checked: boolean) => void
  children: ReactNode
  className?: string
}) {
  return (
    <label className={cx('switch', className)}>
      <input
        className="switch__input"
        type="checkbox"
        role="switch"
        checked={checked}
        onChange={(e) => onChange(e.target.checked)}
      />
      <span className="switch__track" aria-hidden="true" />
      <span className="switch__label">{children}</span>
    </label>
  )
}
