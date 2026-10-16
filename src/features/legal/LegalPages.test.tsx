import { cleanup, render, screen } from '@testing-library/react'
import { afterEach, describe, expect, it } from 'vitest'
import { SupportPage } from './SupportPage'
import { TermsPage } from './TermsPage'

afterEach(cleanup)

describe('Legal pages', () => {
  it('terms: editor, deletion, prohibited content, applicable law, link to privacy', () => {
    render(<TermsPage />)
    expect(
      screen.getByRole('heading', { level: 1, name: 'Conditions générales d’utilisation' }),
    ).toBeTruthy()
    expect(screen.getByText('Elie Bakala')).toBeTruthy()
    expect(screen.getByRole('heading', { name: '6. Ce qui est interdit' })).toBeTruthy()
    expect(screen.getByText(/droit de la République du Congo/)).toBeTruthy()
    expect(screen.getAllByRole('link', { name: /confidentialité/i })[0].getAttribute('href')).toBe(
      '#/confidentialite',
    )
  })

  it('support: a contact address and how to delete the account', () => {
    render(<SupportPage />)
    expect(screen.getByRole('link', { name: 'eliebakala@gmail.com' }).getAttribute('href')).toMatch(
      /^mailto:eliebakala@gmail\.com/,
    )
    expect(screen.getByText('Comment supprimer mon compte ?')).toBeTruthy()
    expect(
      screen.getByRole('link', { name: 'Conditions d’utilisation' }).getAttribute('href'),
    ).toBe('#/conditions')
  })
})
