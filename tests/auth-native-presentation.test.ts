import { describe, expect, it } from 'vitest'
import { renderToStaticMarkup } from 'react-dom/server'
import { createElement } from 'react'
import { AuthPage } from '../src/features/auth/AuthPage'

describe('COVI authentication presentation', () => {
  const props = {
    title: 'Bon retour sur COVI',
    lead: 'Connectez-vous à votre espace de gestion COVI.',
    children: createElement('div', { 'data-testid': 'form-content' }, 'Formulaire'),
  }

  it('keeps marketing content on the web entry screen', () => {
    const html = renderToStaticMarkup(createElement(AuthPage, props))
    expect(html).toContain('Votre activité, mieux pilotée.')
    expect(html).toContain('Boutique')
    expect(html).toContain('Salon de coiffure')
    expect(html).toContain('Formulaire')
    expect(html).not.toContain('auth--native-entry')
  })

  it('shows a focused iOS authentication screen without web marketing content', () => {
    const html = renderToStaticMarkup(createElement(AuthPage, { ...props, nativeIos: true }))
    expect(html).toContain('auth--native-entry')
    expect(html).toContain('Bon retour sur COVI')
    expect(html).toContain('Formulaire')
    expect(html).not.toContain('Votre activité, mieux pilotée.')
    expect(html).not.toContain('Salon de coiffure')
  })
})
