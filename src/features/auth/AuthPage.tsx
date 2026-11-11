import type { ReactNode } from 'react'
import { BrandMark } from '../../components/Brand'
import type { BusinessKind } from '../../lib/businessKinds'

/**
 * Public COVI entry point shared by sign-in and account creation.
 */
export function AuthPage({
  title,
  lead,
  nativeIos = false,
  aside,
  onSectorSelect,
  children,
}: {
  title: string
  lead: string
  nativeIos?: boolean
  /** Shown beside the form on a computer, under it on a phone. */
  aside?: ReactNode
  onSectorSelect?: (kind: BusinessKind) => void
  children: ReactNode
}) {
  return (
    <div className={nativeIos ? "auth auth--native-entry" : "auth"}>
      <main className="auth__layout">
        <header className="auth__intro">
          <div className="auth__brand">
            <BrandMark size={80} />
            <div className="auth__brand-copy">
              <p className="auth__name">COVI</p>
              <p className="auth__tagline">Gestion commerciale</p>
            </div>
          </div>
          {!nativeIos && <h1 className="auth__headline">Votre activité, mieux pilotée.</h1>}
          {!nativeIos && <p className="auth__identity">
            Boutique, restaurant ou salon : ventes, stocks et équipe au même endroit.
          </p>}
          {!nativeIos && <div className="auth__sectors" aria-label="Activités prises en charge par COVI">
            {onSectorSelect ? (
              <>
                <button type="button" className="auth__sector" onClick={() => onSectorSelect('retail')}>Boutique</button>
                <button type="button" className="auth__sector" onClick={() => onSectorSelect('restaurant')}>Restaurant</button>
                <button type="button" className="auth__sector" onClick={() => onSectorSelect('salon')}>Salon de coiffure</button>
              </>
            ) : (
              <>
                <span className="auth__sector">Boutique</span>
                <span className="auth__sector">Restaurant</span>
                <span className="auth__sector">Salon de coiffure</span>
              </>
            )}
          </div>}
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
