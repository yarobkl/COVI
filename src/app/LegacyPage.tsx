import type { ReactNode } from 'react'
import '../styles/legacy.css'

/**
 * Wraps a page that has not been redesigned yet: its old classes only apply inside `.legacy`
 * (src/styles/legacy.css). To be removed with legacy.css in part 2 of the redesign.
 */
export function LegacyPage({ children }: { children: ReactNode }) {
  return <div className="legacy">{children}</div>
}
