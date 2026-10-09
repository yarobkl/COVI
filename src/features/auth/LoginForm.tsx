import type { FormEvent } from 'react'
import { EyeIcon, EyeOffIcon } from '../../components/icons'
import { supabase } from '../../lib/supabase'
import { desktopAuthRedirect, isTauriApp, openOAuthInSystemBrowser } from '../../lib/desktopAuth'
import { authError } from './authErrors'

export type AuthMode = 'login' | 'signup'

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
  async function auth(e: FormEvent<HTMLFormElement>) {
    e.preventDefault()
    onMessage('')
    const f = new FormData(e.currentTarget),
      email = String(f.get('email')).trim(),
      password = String(f.get('password'))
    const r =
      mode === 'login'
        ? await supabase.auth.signInWithPassword({ email, password })
        : await supabase.auth.signUp({ email, password })
    if (r.error) onMessage(authError(r.error))
    else if (mode === 'signup' && !r.data.session)
      onMessage('Compte créé. Vérifiez votre e-mail pour confirmer votre inscription.')
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
          (e as Error).message || 'Impossible d’ouvrir le navigateur pour continuer la connexion.',
        )
      }
    }
  }
  return (
    <div className="authshell">
      <form className="authcard" onSubmit={auth}>
        <div className="authlogo">
          C<span>O</span>VI
        </div>
        <h1>{mode === 'login' ? 'Bienvenue sur COVI' : 'Créer mon compte'}</h1>
        <p>Le système d’exploitation de votre commerce.</p>
        <label>
          E-mail
          <input name="email" type="email" required autoComplete="email" />
        </label>
        <label>
          Mot de passe
          <div className="passwordfield">
            <input
              name="password"
              type={showPassword ? 'text' : 'password'}
              minLength={6}
              required
              autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
            />
            <button
              type="button"
              className="passwordeye"
              aria-label={showPassword ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
              onClick={() => onShowPasswordChange(!showPassword)}
            >
              {showPassword ? <EyeOffIcon /> : <EyeIcon />}
            </button>
          </div>
        </label>
        {message && <p className="authmessage">{message}</p>}
        <button className="primary" type="submit">
          {mode === 'login' ? 'Se connecter' : 'Créer mon compte'}
        </button>
        <div className="authdivider">
          <span>ou</span>
        </div>
        <button className="googleauth" type="button" onClick={googleAuth}>
          <span className="googlemark">G</span>Continuer avec Google
        </button>
        <button
          className="authswitch"
          type="button"
          onClick={() => {
            onModeChange(mode === 'login' ? 'signup' : 'login')
            onMessage('')
          }}
        >
          {mode === 'login' ? 'Première fois ? Créer un compte' : 'J’ai déjà un compte'}
        </button>
        {mode === 'login' && (
          <button className="demo-link" type="button" onClick={onSimulation}>
            Découvrir COVI avec une simulation de 3 mois
          </button>
        )}
      </form>
    </div>
  )
}
