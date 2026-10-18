import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { useState } from 'react'
import { afterEach, describe, expect, it, vi } from 'vitest'
import { supabase } from '../../lib/supabase'
import { LoginForm, type AuthMode } from './LoginForm'

vi.mock('../../lib/supabase', () => ({
  supabase: { auth: { signInWithPassword: vi.fn(), signUp: vi.fn(), signInWithOAuth: vi.fn() } },
}))
vi.mock('../../lib/desktopAuth', () => ({
  isTauriApp: () => false,
  desktopAuthRedirect: () => '',
  openOAuthInSystemBrowser: vi.fn(),
}))

afterEach(cleanup)

function Harness({ onSimulation = vi.fn() }: { onSimulation?: () => void }) {
  const [mode, setMode] = useState<AuthMode>('login')
  const [message, setMessage] = useState('')
  const [show, setShow] = useState(false)
  return (
    <LoginForm
      mode={mode}
      onModeChange={setMode}
      showPassword={show}
      onShowPasswordChange={setShow}
      message={message}
      onMessage={setMessage}
      onSimulation={onSimulation}
    />
  )
}

describe('LoginForm', () => {
  it('signs in and explains a refusal in plain words', async () => {
    vi.mocked(supabase.auth.signInWithPassword).mockResolvedValue({
      data: { user: null, session: null },
      error: { message: 'Invalid login credentials' },
    } as never)
    render(<Harness />)
    expect(screen.getByRole('heading', { name: 'Connexion' })).toBeTruthy()
    fireEvent.change(screen.getByLabelText('Adresse e-mail'), {
      target: { value: ' grace@exemple.cg ' },
    })
    fireEvent.change(screen.getByLabelText('Mot de passe'), { target: { value: 'secret1' } })
    fireEvent.click(screen.getByRole('button', { name: 'Se connecter' }))
    expect(await screen.findByRole('alert')).toHaveProperty(
      'textContent',
      'E-mail ou mot de passe incorrect. Vérifiez et réessayez.',
    )
    expect(supabase.auth.signInWithPassword).toHaveBeenCalledWith({
      email: 'grace@exemple.cg',
      password: 'secret1',
    })
  })

  it('requires the owner identity, company, sector and sends a verification link request', async () => {
    vi.mocked(supabase.auth.signUp).mockResolvedValue({
      data: { user: { id: 'signup-1' }, session: null },
      error: null,
    } as never)
    render(<Harness />)
    fireEvent.click(screen.getByRole('button', { name: 'Créer un compte' }))
    expect(screen.getByRole('radio', { name: 'Restaurant' })).toBeTruthy()
    fireEvent.click(screen.getByRole('radio', { name: 'Restaurant' }))
    fireEvent.change(screen.getByLabelText('Prénom du propriétaire'), {
      target: { value: 'Marie' },
    })
    fireEvent.change(screen.getByLabelText('Nom du propriétaire'), {
      target: { value: 'Balossa' },
    })
    fireEvent.change(screen.getByLabelText('Téléphone du propriétaire'), {
      target: { value: '+242061234567' },
    })
    fireEvent.change(screen.getByLabelText('Nom de votre établissement'), {
      target: { value: 'Chez Marie' },
    })
    fireEvent.change(screen.getByLabelText('Adresse e-mail'), {
      target: { value: 'marie@exemple.cg' },
    })
    fireEvent.change(screen.getByLabelText('Mot de passe'), {
      target: { value: 'Secret123!' },
    })
    fireEvent.change(screen.getByLabelText('Confirmer le mot de passe'), {
      target: { value: 'Secret123!' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Créer mon compte' }))
    await waitFor(() => expect(supabase.auth.signUp).toHaveBeenCalledTimes(1))
    expect(supabase.auth.signUp).toHaveBeenCalledWith({
      email: 'marie@exemple.cg',
      password: 'Secret123!',
      options: {
        emailRedirectTo: window.location.origin,
        data: {
          first_name: 'Marie',
          last_name: 'Balossa',
          full_name: 'Marie Balossa',
          phone_number: '+242061234567',
          business_kind: 'restaurant',
          business_name: 'Chez Marie',
        },
      },
    })
    expect(screen.getByText(/e-mail de confirmation est envoyé/)).toBeTruthy()
  })

  it('refuses a mismatched password before contacting Supabase', async () => {
    vi.mocked(supabase.auth.signUp).mockClear()
    render(<Harness />)
    fireEvent.click(screen.getByRole('button', { name: 'Créer un compte' }))
    fireEvent.change(screen.getByLabelText('Prénom du propriétaire'), {
      target: { value: 'Awa' },
    })
    fireEvent.change(screen.getByLabelText('Nom du propriétaire'), {
      target: { value: 'Koumba' },
    })
    fireEvent.change(screen.getByLabelText('Téléphone du propriétaire'), {
      target: { value: '+242061234567' },
    })
    fireEvent.change(screen.getByLabelText('Nom de votre établissement'), {
      target: { value: 'Awa Boutique' },
    })
    fireEvent.change(screen.getByLabelText('Adresse e-mail'), {
      target: { value: 'awa@exemple.cg' },
    })
    fireEvent.change(screen.getByLabelText('Mot de passe'), {
      target: { value: 'Secret123!' },
    })
    fireEvent.change(screen.getByLabelText('Confirmer le mot de passe'), {
      target: { value: 'Different123!' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Créer mon compte' }))
    expect(screen.getByText('Les deux mots de passe ne correspondent pas.')).toBeTruthy()
    expect(supabase.auth.signUp).not.toHaveBeenCalled()
  })

  it('shows Google and Facebook side by side and keeps OAuth flows live', async () => {
    vi.mocked(supabase.auth.signInWithOAuth).mockResolvedValue({
      data: { provider: 'google', url: 'https://example.com/google' },
      error: null,
    } as never)
    render(<Harness />)
    const group = screen.getByRole('group', { name: 'Connexion avec un compte externe' })
    expect(group.querySelectorAll('button')).toHaveLength(2)
    expect(group.querySelector('button:first-child')?.textContent).toContain('Google')
    expect(group.querySelector('button:last-child')?.textContent).toContain('Facebook')
    fireEvent.click(screen.getByRole('button', { name: 'Google' }))
    await waitFor(() =>
      expect(supabase.auth.signInWithOAuth).toHaveBeenCalledWith({
        provider: 'google',
        options: { redirectTo: window.location.origin, skipBrowserRedirect: false },
      }),
    )
    fireEvent.click(screen.getByRole('button', { name: 'Facebook' }))
    await waitFor(() =>
      expect(supabase.auth.signInWithOAuth).toHaveBeenCalledWith({
        provider: 'facebook',
        options: {
          redirectTo: window.location.origin,
          skipBrowserRedirect: false,
          scopes: 'email',
        },
      }),
    )
  })

  it('switches to sign-up, shows the password and opens the example shop', () => {
    const onSimulation = vi.fn()
    render(<Harness onSimulation={onSimulation} />)
    fireEvent.click(screen.getByRole('button', { name: 'Voir une boutique d’exemple' }))
    expect(onSimulation).toHaveBeenCalled()
    fireEvent.click(screen.getByRole('button', { name: 'Afficher le mot de passe' }))
    expect(screen.getByLabelText('Mot de passe').getAttribute('type')).toBe('text')
    fireEvent.click(screen.getByRole('button', { name: 'Créer un compte' }))
    expect(screen.getByRole('heading', { name: 'Créer votre compte' })).toBeTruthy()
    expect(screen.getByText('6 caractères minimum.')).toBeTruthy()
    expect(screen.getByRole('button', { name: 'me connecter' })).toBeTruthy()
  })
})
