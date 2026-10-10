import type { ReactNode } from 'react'

export type IconProps = {
  /** Extra classes, e.g. `icon--sm` (18 px) or `icon--lg` (32 px). Buttons size their icons. */
  className?: string
}

/**
 * Hand-drawn line icon on a 24 × 24 grid: 1.75 px stroke, round caps and joins, current text
 * colour. Always decorative (`aria-hidden`): the visible text or the button's `aria-label` names it.
 */
export function Icon({ className, children }: IconProps & { children: ReactNode }) {
  return (
    <svg
      className={className ? `icon ${className}` : 'icon'}
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.75}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      focusable="false"
    >
      {children}
    </svg>
  )
}
