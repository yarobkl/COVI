import { useState, type FormEvent } from 'react'
import { EyeIcon, EyeOffIcon } from '../../components/icons'
import { Button, Field, IconButton, Input, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { desktopAuthRedirect, isTauriApp, openOAuthInSystemBrowser } from '../../lib/desktopAuth'
import { AuthPage } from './AuthPage'
import { authError } from './authErrors'
import { legalLinks } from '../../lib/legal'
import { BUSINESS_KINDS, type BusinessKind } from '../../lib/businessKinds'
import { createOwnerSignupDetails, storeOwnerOAuthIntent } from '../../lib/ownerSignup'

export type AuthMode = 'login' | 'signup'

/** Messages of this screen that are good news, not errors. */
const isGoodNews = (message: string) => message.startsWith('Compte créé')

/** Official-color brand marks, kept local so sign-in buttons need no third-party assets. */
function GoogleLogo() {
  return (
    <svg className="auth__social-logo" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill="#4285F4"
        d="M21.35 11.1H12v3.8h5.35c-.23 1.21-.93 2.24-1.98 2.93v2.43h3.2c1.87-1.73 2.95-4.29 2.95-7.32 0-.62-.06-1.22-.17-1.84Z"
      />
      <path
        fill="#34A853"
        d="M12 22c2.7 0 4.96-.9 6.61-2.44l-3.2-2.43c-.89.59-2.03.94-3.41.94-2.62 0-4.84-1.77-5.64-4.15H3.07v2.5A10 10 0 0 0 12 22Z"
      />
      <path
        fill="#FBBC05"
        d="M6.36 13.92A6.01 6.01 0 0 1 6.04 12c0-.66.11-1.31.32-1.92v-2.5H3.07A10 10 0 0 0 2 12c0 1.61.39 3.13 1.07 4.42l3.29-2.5Z"
      />
      <path
        fill="#EA4335"
        d="M12 5.93c1.43 0 2.72.49 3.74 1.47l2.8-2.8C16.84 2.99 14.63 2 12 2a10 10 0 0 0-8.93 5.58l3.29 2.5C7.16 7.7 9.38 5.93 12 5.93Z"
      />
    </svg>
  )
}

/** Apple mark, white on the black « Continuer avec Apple » button (Apple's design rules). */
function AppleLogo() {
  return (
    <svg className="auth__social-logo" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill="currentColor"
        d="M16.37 1.43c0 1.14-.5 2.27-1.18 3.08-.74.9-1.99 1.57-2.99 1.57-.12 0-.23-.02-.3-.03-.01-.06-.04-.22-.04-.39 0-1.15.57-2.27 1.21-2.98.8-.94 2.14-1.64 3.25-1.68.03.13.05.28.05.43Zm4.56 15.71c-.03.07-.46 1.58-1.52 3.12-.94 1.34-1.94 2.71-3.43 2.71-1.52 0-1.9-.88-3.63-.88-1.7 0-2.3.91-3.67.91-1.38 0-2.33-1.26-3.43-2.8C3.96 18.38 2.93 15.57 2.93 12.92c0-4.28 2.8-6.55 5.55-6.55 1.45 0 2.68.95 3.6.95.87 0 2.22-1.01 3.9-1.01.61 0 2.89.06 4.38 2.19-.13.09-2.39 1.37-2.39 4.19 0 3.26 2.86 4.42 2.96 4.45Z"
      />
    </svg>
  )
}

/**
 * « Continuer avec Apple » : obligatoire sur l'App Store dès que Google ou Facebook sont proposés.
 * Affiché seulement quand le fournisseur Apple est configuré dans Supabase
 * (VITE_COVI_APPLE_SIGNIN=true ; voir docs/connexion-apple.md).
 */
export const appleSignInEnabled = import.meta.env.VITE_COVI_APPLE_SIGNIN === 'true'

function FacebookLogo() {
  return (
    <svg className="auth__social-logo" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path
        fill="#1877F2"
        d="M24 12a12 12 0 1 0-13.875 11.854v-8.385H7.078V12h3.047V9.356c0-3.007 1.791-4.668 4.532-4.668 1.312 0 2.686.234 2.686.234v2.953h-1.514c-1.491 0-1.956.925-1.956 1.874V12h3.328l-.532 3.469h-2.796v8.385A12.004 12.004 0 0 0 24 12Z"
      />
      <path
        fill="#fff"
        d="M16.672 15.469 17.204 12h-3.328V9.75c0-.949.465-1.874 1.956-1.874h1.514V4.923s-1.374-.234-2.686-.234c-2.741 0-4.532 1.661-4.532 4.668V12H7.078v3.469h3.047v8.385a12.124 12.124 0 0 0 3.75 0v-8.385h2.797Z"
      />
    </svg>
  )
}

/** E-mail / Apple / Google / Facebook sign-in and sign-up. Its state lives in AuthGate so it survives sign-out. */
export function LoginForm({
  mode,
  onModeChange,
  showPassword,
  onShowPasswordChange,
  message,
  onMessage,
  onSimulation,
}: {
  mode: AuthMode
  onModeChange: (mode: AuthMode) => void
  showPassword: boolean
  onShowPasswordChange: (show: boolean) => void
  message: string
  onMessage: (message: string) => void
  onSimulation: () => void
}) {
  const [busy, setBusy] = useState(false)
  const [selectedKind, setSelectedKind] = useState<BusinessKind>('retail')
  const login = mode === 'login'

  async function auth(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    onMessage('')
    const f = new FormData(e.currentTarget)
    const email = String(f.get('email')).trim()
    const password = String(f.get('password'))
    let signupDetails: ReturnType<typeof createOwnerSignupDetails> | null = null
    if (!login) {
      if (password !== String(f.get('confirm-password'))) {
        onMessage('Les deux mots de passe ne correspondent pas.')
        return
      }
      try {
        signupDetails = createOwnerSignupDetails({
          firstName: String(f.get('first-name') ?? ''),
          lastName: String(f.get('last-name') ?? ''),
          phone: String(f.get('phone') ?? ''),
          businessKind: selectedKind,
          businessName: String(f.get('business-name') ?? ''),
        })
      } catch (error) {
        onMessage(error instanceof Error ? error.message : 'Veuillez vérifier le formulaire.')
        return
      }
    }
    setBusy(true)
    try {
      const r = login
        ? await supabase.auth.signInWithPassword({ email, password })
        : await supabase.auth.signUp({
            email,
            password,
            options: { data: signupDetails!, emailRedirectTo: window.location.origin },
          })
      if (r.error) onMessage(authError(r.error))
      else if (!login && !r.data.session)
        onMessage(
          `Si cette adresse peut être inscrite, un e-mail de confirmation est envoyé à ${email}. Ouvrez son lien pour activer votre compte avant de vous connecter.`,
        )
      else if (!login && r.data.session) {
        // Never pretend the verification link was sent when Auth email confirmation is disabled.
        onMessage(
          'Inscription enregistrée, mais la confirmation obligatoire par e-mail n’est pas activée côté serveur. Contactez le support COVI.',
        )
      }
    } finally {
      setBusy(false)
    }
  }

  async function socialAuth(provider: 'google' | 'facebook' | 'apple') {
    if (busy) return
    onMessage('')
    setBusy(true)
    try {
      if (!login) {
        // Retain the user's activity choice through the external OAuth redirect.
        const company = (document.querySelector('input[name="business-name"]') as HTMLInputElement | null)?.value ?? ''
        storeOwnerOAuthIntent(selectedKind, company)
      }
      const desktop = isTauriApp()
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo: desktop ? desktopAuthRedirect() : window.location.origin,
          skipBrowserRedirect: desktop,
          ...(provider === 'facebook' ? { scopes: 'email' } : {}),
          ...(provider === 'apple' ? { scopes: 'name email' } : {}),
        },
      })
      if (error) {
        onMessage(authError(error))
        return
      }
      if (desktop && data.url) await openOAuthInSystemBrowser(data.url)
    } catch (e) {
      onMessage((e as Error).message || 'Connexion impossible. Vérifiez votre réseau et réessayez.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <AuthPage
      title={login ? 'Connexion' : 'Créer votre compte'}
      lead={
        login
          ? 'Connectez-vous à votre espace de gestion COVI.'
          : 'Présentez-vous, puis choisissez votre métier et le nom de votre établissement.'
      }
      aside={
        login && (
          <section className="sheet auth__example" aria-labelledby="exemple-titre">
            <h2 className="sheet__title" id="exemple-titre">
              Vous découvrez COVI ?
            </h2>
            <p>
              Voyez trois mois dans une boutique de Poto-Poto : ventes, arrivages, ballons et
              charges. Rien de ce que vous voyez ne touche votre boutique.
            </p>
            <Button variant="secondary" onClick={onSimulation}>
              Voir une boutique d’exemple
            </Button>
          </section>
        )
      }
    >
      <form className="auth__form" onSubmit={auth}>
        {!login && (
          <>
            <fieldset>
              <legend>Votre secteur d’activité</legend>
              {BUSINESS_KINDS.map((kind) => (
                <label key={kind.value} style={{ display: 'block', marginTop: '0.65rem' }}>
                  <input
                    type="radio"
                    name="business-kind"
                    value={kind.value}
                    checked={selectedKind === kind.value}
                    onChange={() => setSelectedKind(kind.value)}
                    required
                  />{' '}
                  {kind.label}
                </label>
              ))}
            </fieldset>
            <Field label="Prénom du propriétaire">
              {(control) => (
                <Input {...control} name="first-name" autoComplete="given-name" minLength={2} maxLength={80} required />
              )}
            </Field>
            <Field label="Nom du propriétaire">
              {(control) => (
                <Input {...control} name="last-name" autoComplete="family-name" minLength={2} maxLength={80} required />
              )}
            </Field>
            <Field label="Téléphone du propriétaire" hint="Format international, par exemple +242061234567.">
              {(control) => (
                <Input {...control} type="tel" name="phone" autoComplete="tel" placeholder="+242061234567" maxLength={32} required />
              )}
            </Field>
            <Field label="Nom de votre établissement">
              {(control) => (
                <Input {...control} name="business-name" autoComplete="organization" placeholder={BUSINESS_KINDS.find((kind) => kind.value === selectedKind)?.example} minLength={2} maxLength={120} required />
              )}
            </Field>
          </>
        )}
        <Field label="Adresse e-mail">
          {(control) => (
            <Input {...control} name="email" type="email" required autoComplete="email" />
          )}
        </Field>
        <Field label="Mot de passe" hint={login ? undefined : '6 caractères minimum.'}>
          {(control) => (
            <div className="password">
              <Input
                {...control}
                name="password"
                type={showPassword ? 'text' : 'password'}
                minLength={6}
                required
                autoComplete={login ? 'current-password' : 'new-password'}
              />
              <IconButton
                className="password__toggle"
                label={showPassword ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
                onClick={() => onShowPasswordChange(!showPassword)}
              >
                {showPassword ? <EyeOffIcon /> : <EyeIcon />}
              </IconButton>
            </div>
          )}
        </Field>
        {!login && (
          <Field label="Confirmer le mot de passe">
            {(control) => (
              <Input
                {...control}
                name="confirm-password"
                type={showPassword ? 'text' : 'password'}
                minLength={6}
                required
                autoComplete="new-password"
              />
            )}
          </Field>
        )}
        {message && (
          <Notice tone={isGoodNews(message) ? 'success' : 'danger'}>
            <p>{message}</p>
          </Notice>
        )}
        <Button variant="primary" size="lg" block type="submit" busy={busy}>
          {login ? 'Se connecter' : 'Créer mon compte'}
        </Button>
        <p className="auth__or" aria-hidden="true">
          ou
        </p>
        {appleSignInEnabled && (
          <Button
            variant="secondary"
            size="lg"
            block
            className="auth__apple"
            disabled={busy}
            onClick={() => void socialAuth('apple')}
          >
            <AppleLogo />
            Continuer avec Apple
          </Button>
        )}
        <Button
          variant="secondary"
          size="lg"
          block
          onClick={() => void socialAuth('google')}
          disabled={busy}
        >
          <GoogleLogo />
          Continuer avec Google
        </Button>
        <Button
          variant="secondary"
          size="lg"
          block
          disabled={busy}
          onClick={() => void socialAuth('facebook')}
        >
          <FacebookLogo />
          Continuer avec Facebook
        </Button>
      </form>
      <p className="auth__switch">
        {login ? 'Pas encore de compte ?' : 'J’ai déjà un compte,'}{' '}
        <button
          type="button"
          className="auth__link"
          onClick={() => {
            onModeChange(login ? 'signup' : 'login')
            onMessage('')
          }}
        >
          {login ? 'Créer un compte' : 'me connecter'}
        </button>
      </p>
      {!login && (
        <p className="auth__legal">
          En créant un compte, vous acceptez les <a href="#/conditions">conditions d’utilisation</a>{' '}
          et la <a href="#/confidentialite">politique de confidentialité</a>.
        </p>
      )}
      <nav className="auth__legal" aria-label="Informations légales">
        {legalLinks.map((l) => (
          <a key={l.href} href={l.href}>
            {l.label}
          </a>
        ))}
      </nav>
    </AuthPage>
  )
}
