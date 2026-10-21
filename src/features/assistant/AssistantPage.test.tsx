import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { AssistantPage } from './AssistantPage'
import { askCoviAssistant } from '../../lib/assistant'

vi.mock('../../lib/assistant', () => ({ askCoviAssistant: vi.fn() }))

const shop = {
  id: '11111111-1111-4111-8111-111111111111',
  name: 'Boutique test',
  city: 'Brazzaville',
  country: 'Congo',
  currency: 'XAF',
  business_kind: 'retail',
}

describe('AssistantPage', () => {
  beforeEach(() => vi.clearAllMocks())
  afterEach(cleanup)

  it('requires explicit consent before sending a question to Gemini', async () => {
    vi.mocked(askCoviAssistant).mockResolvedValue('Ce montant ne représente pas le bénéfice net.')
    render(<AssistantPage shop={shop} />)
    fireEvent.change(screen.getByLabelText('Votre question'), { target: { value: 'Mes ventes ?' } })
    const send = screen.getByRole('button', { name: 'Envoyer ma question' })
    expect((send as HTMLButtonElement).disabled).toBe(true)
    expect(askCoviAssistant).not.toHaveBeenCalled()
    fireEvent.click(screen.getByRole('checkbox'))
    expect((send as HTMLButtonElement).disabled).toBe(false)
    fireEvent.click(send)
    await waitFor(() => expect(askCoviAssistant).toHaveBeenCalledWith(shop.id, 'Mes ventes ?'))
    expect(await screen.findByText('Ce montant ne représente pas le bénéfice net.')).toBeTruthy()
  })

  it('does not promise real financial data for the restaurant', () => {
    render(<AssistantPage shop={{ ...shop, business_kind: 'restaurant' }} />)
    expect(
      screen.getByText(
        /les chiffres financiers du restaurant ou du salon ne sont pas encore connectés/i,
      ),
    ).toBeTruthy()
    expect(
      screen.getByRole('button', { name: 'Comment réduire le gaspillage alimentaire ?' }),
    ).toBeTruthy()
  })
})
