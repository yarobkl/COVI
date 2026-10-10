import type { ReactNode } from 'react'
import { LabelCard } from '../../components/ui'

/**
 * A page of the notebook before the shop is open (connexion, création) : the COVI label, a title
 * that says what the screen does, then the form.
 */
export function AuthPage({
  title,
  lead,
  aside,
  children,
}: {
  title: string
  lead: string
  /** Shown beside the form on a computer, under it on a phone. */
  aside?: ReactNode
  children: ReactNode
}) {
  return (
    <div className="auth">
      <main className="auth__sheet seyes margin-rule">
        <LabelCard className="auth__brand">
          <p className="auth__name">COVI</p>
          <p className="auth__tagline">Le cahier de la boutique.</p>
        </LabelCard>
        <div className="auth__grid">
          <div className="auth__main">
            <h1>{title}</h1>
            <p className="auth__lead">{lead}</p>
            {children}
          </div>
          {aside && <div className="auth__aside">{aside}</div>}
        </div>
      </main>
    </div>
  )
}
