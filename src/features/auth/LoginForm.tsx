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

/** E-mail / Google sign-in and sign-up. Its state lives in AuthGate so it survives sign-out. */
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

  async function googleAuth() {
    onMessage('')
    const desktop = isTauriApp()
    const { data, error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: {
        redirectTo: desktop ? desktopAuthRedirect() : window.location.origin,
        skipBrowserRedirect: desktop,
      },
    })
    if (error) {
      onMessage(authError(error))
      return
    }
    if (desktop && data.url) {
      try {
        await openOAuthInSystemBrowser(data.url)
      } catch (e) {
        onMessage(
          (e as Error).message ||
            'Le navigateur ne s’est pas ouvert. Réessayez, ou connectez-vous avec votre e-mail.',
        )
      }
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
        <Button variant="secondary" size="lg" block onClick={() => void googleAuth()}>
          Continuer avec Google
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
