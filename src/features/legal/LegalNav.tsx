import type { ReactNode } from 'react'
import { legalLinks } from '../../lib/legal'

/** Une partie d'une page légale : titre souligné au stylo rouge, puis le texte. */
export function LegalPart({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="legal__part">
      <h2 className="section-title">{title}</h2>
      {children}
    </section>
  )
}

/** Bas des pages légales : les deux autres pages et le retour à COVI. */
export function LegalNav({ current }: { current: string }) {
  return (
    <nav className="legal__nav" aria-label="Informations légales">
      {legalLinks
        .filter((l) => l.href !== current)
        .map((l) => (
          <a key={l.href} href={l.href}>
            {l.label}
          </a>
        ))}
      <a href="#/">← Revenir à COVI</a>
    </nav>
  )
}
