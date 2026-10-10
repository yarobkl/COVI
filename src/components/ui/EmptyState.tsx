import type { ReactNode } from 'react'

/** A notebook page with a pen: the default drawing of an empty state. */
function NotebookArt() {
  return (
    <svg className="empty__art" viewBox="0 0 64 72" aria-hidden="true" focusable="false">
      <path d="M8 6h40l8 8v52H8Z" />
      <path d="M48 6v8h8M16 26h28M16 36h28M16 46h16" stroke="var(--line)" />
      <path d="M14 18v48" stroke="var(--margin-line)" />
      <path d="M40 58 56 42l4 4-16 16-6 2Z" stroke="var(--action)" />
    </svg>
  )
}

/**
 * Nothing to show yet: what is missing and what to do. Aligned on the margin, never centred in
 * the middle of the screen.
 */
export function EmptyState({
  title,
  art,
  actions,
  children,
}: {
  title: ReactNode
  art?: ReactNode
  actions?: ReactNode
  children?: ReactNode
}) {
  return (
    <div className="empty">
      {art ?? <NotebookArt />}
      <p className="empty__title">{title}</p>
      {children && <div className="empty__text">{children}</div>}
      {actions && <div className="empty__actions">{actions}</div>}
    </div>
  )
}
