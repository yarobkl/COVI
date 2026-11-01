import type { ReactNode } from 'react'
import { BrandMark } from '../../components/Brand'

/**
 * Public COVI entry point shared by sign-in and account creation.
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
      <main className="auth__layout">
        <header className="auth__intro">
          <div className="auth__brand">
            <BrandMark size={44} />
            <div className="auth__brand-copy">
              <p className="auth__name">COVI</p>
              <p className="auth__tagline">Gestion commerciale</p>
            </div>
          </div>
          <h1 className="auth__headline">Votre activité, mieux pilotée.</h1>
          <p className="auth__identity">
            Boutique, restaurant ou salon : ventes, stocks et équipe au même endroit.
          </p>
          <div className="auth__sectors" aria-label="Activités prises en charge par COVI">
            <span className="auth__sector">Boutique</span>
            <span className="auth__sector">Restaurant</span>
            <span className="auth__sector">Salon de coiffure</span>
          </div>
        </header>
        <section className="auth__panel" aria-labelledby="auth-title">
          <div className="auth__main">
            <h2 id="auth-title">{title}</h2>
            <p className="auth__lead">{lead}</p>
            {children}
          </div>
        </section>
        {aside && <aside className="auth__aside">{aside}</aside>}
      </main>
    </div>
  )
}
