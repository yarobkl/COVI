import type { ReactNode } from 'react'

/**
 * Head of a page of the notebook: the title underlined in red pen, one sentence under it and,
 * on the right, the page's main action. The same on every page.
 */
export function PageHead({
  title,
  sub,
  action,
}: {
  title: ReactNode
  sub?: ReactNode
  action?: ReactNode
}) {
  return (
    <header className="page-head">
      <div className="page-head__text">
        <h1 className="page-title">{title}</h1>
        {sub && <p className="page-head__sub">{sub}</p>}
      </div>
      {action}
    </header>
  )
}

/** Short message after an action (« Charge enregistrée. »), read out by screen readers. */
export function PageMessage({ children }: { children: ReactNode }) {
  return (
    <p className="page-msg" role="status">
      {children}
    </p>
  )
}
