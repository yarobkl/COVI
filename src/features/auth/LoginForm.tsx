import { useState, type FormEvent } from 'react'
import { EyeIcon, EyeOffIcon } from '../../components/icons'
import { Button, Field, IconButton, Input, Notice } from '../../components/ui'
import { supabase } from '../../lib/supabase'
import { desktopAuthRedirect, isTauriApp, openOAuthInSystemBrowser } from '../../lib/desktopAuth'
import { AuthPage } from './AuthPage'
import { authError } from './authErrors'

export type AuthMode = 'login' | 'signup'

/** Messages of this screen that are good news, not errors. */
const isGoodNews = (message: string) => message.startsWith('Compte créé')


/** Official-color brand marks, kept local so sign-in buttons need no third-party assets. */
function GoogleLogo() {
  return (
    <svg className="auth__social-logo" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path fill="#4285F4" d="M21.35 11.1H12v3.8h5.35c-.23 1.21-.93 2.24-1.98 2.93v2.43h3.2c1.87-1.73 2.95-4.29 2.95-7.32 0-.62-.06-1.22-.17-1.84Z" />
      <path fill="#34A853" d="M12 22c2.7 0 4.96-.9 6.61-2.44l-3.2-2.43c-.89.59-2.03.94-3.41.94-2.62 0-4.84-1.77-5.64-4.15H3.07v2.5A10 10 0 0 0 12 22Z" />
      <path fill="#FBBC05" d="M6.36 13.92A6.01 6.01 0 0 1 6.04 12c0-.66.11-1.31.32-1.92v-2.5H3.07A10 10 0 0 0 2 12c0 1.61.39 3.13 1.07 4.42l3.29-2.5Z" />
      <path fill="#EA4335" d="M12 5.93c1.43 0 2.72.49 3.74 1.47l2.8-2.8C16.84 2.99 14.63 2 12 2a10 10 0 0 0-8.93 5.58l3.29 2.5C7.16 7.7 9.38 5.93 12 5.93Z" />
    </svg>
  )
}

function FacebookLogo() {
  return (
    <svg className="auth__social-logo" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
      <path fill="#1877F2" d="M24 12a12 12 0 1 0-13.875 11.854v-8.385H7.078V12h3.047V9.356c0-3.007 1.791-4.668 4.532-4.668 1.312 0 2.686.234 2.686.234v2.953h-1.514c-1.491 0-1.956.925-1.956 1.874V12h3.328l-.532 3.469h-2.796v8.385A12.004 12.004 0 0 0 24 12Z" />
      <path fill="#fff" d="M16.672 15.469 17.204 12h-3.328V9.75c0-.949.465-1.874 1.956-1.874h1.514V4.923s-1.374-.234-2.686-.234c-2.741 0-4.532 1.661-4.532 4.668V12H7.078v3.469h3.047v8.385a12.124 12.124 0 0 0 3.75 0v-8.385h2.797Z" />
    </svg>
  )
}

/** E-mail / Google / Facebook sign-in and sign-up. Its state lives in AuthGate so it survives sign-out. */
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
  const login = mode === 'login'

  async function auth(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    onMessage('')
    const f = new FormData(e.currentTarget),
      email = String(f.get('email')).trim(),
      password = String(f.get('password'))
    setBusy(true)
    try {
      const r = login
        ? await supabase.auth.signInWithPassword({ email, password })
        : await supabase.auth.signUp({ email, password })
      if (r.error) onMessage(authError(r.error))
      else if (!login && !r.data.session)
        onMessage(
          `Compte créé. Un e-mail vient de partir vers ${email} : ouvrez-le pour confirmer, puis connectez-vous.`,
        )
    } finally {
      setBusy(false)
    }
  }

  async function socialAuth(provider: 'google' | 'facebook') {
    if (busy) return
    onMessage('')
    setBusy(true)
    try {
      const desktop = isTauriApp()
      const { data, error } = await supabase.auth.signInWithOAuth({
        provider,
        options: {
          redirectTo: desktop ? desktopAuthRedirect() : window.location.origin,
          skipBrowserRedirect: desktop,
          ...(provider === 'facebook' ? { scopes: 'email' } : {}),
        },
      })
      if (error) {
        onMessage(authError(error))
        return
      }
      if (desktop && data.url) await openOAuthInSystemBrowser(data.url)
    } catch (e) {
      onMessage(
        (e as Error).message ||
          'Connexion impossible. Vérifiez votre réseau et réessayez.',
      )
    } finally {
      setBusy(false)
    }
  }

  return (
    <AuthPage
      title={login ? 'Connexion' : 'Créer votre compte'}
      lead={
        login
          ? 'Connectez-vous pour ouvrir la boutique.'
          : 'Quelques secondes, et votre boutique est prête.'
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
        <Button variant="secondary" size="lg" block onClick={() => void socialAuth('google')} disabled={busy}>
          <GoogleLogo />
          Continuer avec Google
        </Button>
        <Button variant="secondary" size="lg" block disabled={busy} onClick={() => void socialAuth('facebook')}>
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
    </AuthPage>
  )
}
