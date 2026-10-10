import { describe, expect, it } from 'vitest'
import { authError } from './authErrors'

const e = (message: string) => ({ message })

describe('authError', () => {
  it('says what happened and what to do', () => {
    expect(authError(e('Invalid login credentials'))).toBe(
      'E-mail ou mot de passe incorrect. Vérifiez et réessayez.',
    )
    expect(authError(e('Email not confirmed'))).toMatch(/^Confirmez d’abord votre adresse/)
    expect(authError(e('User already registered'))).toBe(
      'Cette adresse a déjà un compte. Connectez-vous plutôt.',
    )
    expect(authError(e('Password should be at least 6 characters.'))).toBe(
      'Mot de passe trop court : 6 caractères minimum.',
    )
    expect(authError(e('Shop name is required'))).toBe('Indiquez le nom de la boutique.')
    expect(authError(e('Failed to fetch'))).toBe(
      'Pas de réseau. Réessayez quand la connexion revient.',
    )
  })

  it('does not blame the password length for every password error', () => {
    expect(authError(e('New password should be different from the old password.'))).toBe(
      'Ça n’a pas marché. Vérifiez l’e-mail et le mot de passe, puis réessayez.',
    )
    expect(authError(null)).toBe(
      'Ça n’a pas marché. Vérifiez l’e-mail et le mot de passe, puis réessayez.',
    )
  })
})
