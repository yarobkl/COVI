import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { PrivacyPage } from './PrivacyPage'

afterEach(cleanup)

describe('PrivacyPage', () => {
  it('names the editor, the contact, where data lives and how to delete the account', () => {
    render(<PrivacyPage />)
    expect(
      screen.getByRole('heading', { level: 1, name: 'Politique de confidentialité' }),
    ).toBeTruthy()
    expect(screen.getByText('Elie Bakala')).toBeTruthy()
    expect(
      screen.getAllByRole('link', { name: 'eliebakala@gmail.com' })[0].getAttribute('href'),
    ).toMatch(/^mailto:eliebakala@gmail\.com/)
    expect(screen.getByText(/serveurs situés à Paris/)).toBeTruthy()
    expect(screen.getByText('Ma boutique → Supprimer mon compte')).toBeTruthy()
  })
})
