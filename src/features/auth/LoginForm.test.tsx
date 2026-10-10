import { cleanup, fireEvent, render, screen } from '@testing-library/react'
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
